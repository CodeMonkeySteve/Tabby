# frozen_string_literal: true

require 'alpha_tab'

class Song < ApplicationRecord
  include PassiveColumns
  extend FriendlyId
  include Song::Songsterr
  include Song::CoverArt

  INSTRUMENT_TYPES = [
    :drums,     # drums and percussion
    :bass,      # electric, acoustic, fretless
    :guitar,    # electric, acoustic, banjo, mandolin, ukulele
    :keys,      # piano, synth, organ, accordion, pitched percussion
    :vocals,    # lead, backing, choir, synth voice
    :strings,   # violin, viola, cello, other orchestral
    :brass,     # trumpet, trombone, french horn, tuba, other brass
    :woodwinds, # saxophone, clarinet, oboe, flute, whistle
    :other      # harmonica, sitar, theramin, etc. (only on Song)
  ].freeze

  # replaced by SongsterrSong, until it's dropped
  self.ignored_columns += %w[songsterr_id]

  # The instrument type of each score track, in track order (so not a torque-postgresql EnumSet, which is unordered and unique)
  attribute :track_types, :string, array: true, default: []

  validates :title, presence: true
  validates :score_data, presence: true
  validates :track_types, instrument_types: true

  friendly_id :title_and_artist, use: %i[sequentially_slugged history reserved], reserved_words: %w[new], treat_reserved_as_conflict: true

  # only needed by the player
  passive_columns :sync_points

  has_many :play_histories
  has_one :songsterr_song, autosave: true
  has_many :notes, class_name: 'SongNote'

  # The current user's note, e.g. `song.note || song.build_note`
  has_one :note, -> { where(user: Current.user) }, class_name: 'SongNote'
  has_many :alternate_tabs

  # Songs whose title or artist contains each word of the query (or all songs, for a blank query)
  scope :search, ->(query) do
    query.to_s.split.reduce(all) do |songs, word|
      pattern = "%#{sanitize_sql_like(word)}%"
      songs.where('title ILIKE :pattern OR artist ILIKE :pattern', pattern:)
    end
  end

  # Songs sorted by 'artist', 'newest' (added), or 'played' (most recently by the user), or by title for any other sort
  scope :sorted, ->(sort, user: Current.user) do
    case sort
    when 'artist' then order(:artist, :title)
    when 'newest' then order(created_at: :desc)
    when 'played'
      last_played = PlayHistory.where(user:).group(:song_id).select(:song_id, 'MAX(date) AS last_played_on')
      joins("LEFT JOIN (#{last_played.to_sql}) plays ON plays.song_id = songs.id")
        .order(Arel.sql('plays.last_played_on DESC NULLS LAST'), :title, :artist)
    else order(:title, :artist)
    end
  end

  # Songs with a track for any of the given instrument types (or all songs, if none are given)
  scope :for_instruments, ->(types) { types.empty? ? all : where('track_types && ARRAY[?]::instrument_type[]', types) }

  after_destroy { Playlist.where('? = ANY(song_ids)', id).update_all(['song_ids = array_remove(song_ids, ?)', id]) }

  include ScoreUploader::Attachment(:score)
  include ApplicationUploader::Attachment(:audio)
  include ImageUploader::Attachment(:cover)

  # (Re)classify the tracks of a new score, unless their types were given with it
  before_validation :classify_tracks, if: -> { will_save_change_to_score_data? && !will_save_change_to_track_types? }

  # Saved playback ranges (score ticks) and track settings (by score track index) may not fit a new score
  after_update :clear_note_score_settings, if: :saved_change_to_score_data?

  # Alternate tabs index the old score's notes
  after_update :delete_alternate_tabs, if: :saved_change_to_score_data?

  # The saved slug, for URLs that work while the song has unsaved changes, e.g. redisplaying the edit form with a new title
  def to_param
    slug_in_database || super
  end

  def should_generate_new_friendly_id?
    will_save_change_to_title? || will_save_change_to_artist? || super
  end

  # Joins "'s" into its word ("Rock 'n' Roll's" to "rock-n-rolls"), instead of separating it with a hyphen
  def normalize_friendly_id(value)
    super(value.to_s.gsub(/['’](s)\b/i, '\\1'))
  end

  # The distinct instrument types of the score tracks, in INSTRUMENT_TYPES order
  def instrument_types
    INSTRUMENT_TYPES.map(&:to_s) & track_types
  end

  # The indexes of the score tracks played by any of the given instrument types
  def track_indexes_for(types)
    track_types.each_index.select { types.include?(track_types[it]) }
  end

  # The instrument type of each track described by AlphaTab#score_info
  def self.track_types_from(info)
    info['tracks'].map { Song::Track.from_info(it).instrument_type }
  end

  # The score's tracks, as read by AlphaTab (raising Nodo::Error or Shrine::FileNotFound if it can't be)
  def score_tracks
    @score_tracks = nil if @score_tracks_id != score&.id
    @score_tracks_id = score&.id
    @score_tracks ||= score ? score.download { AlphaTab.new.score_info(it.path) }['tracks'].map { Song::Track.from_info(it) } : []
  end

  # Sets the instrument type of each score track (see Song::Track), or adds an error if the score is missing or unreadable
  def classify_tracks
    score && score_attacher.errors.empty? or return

    self.track_types = score_tracks.map(&:instrument_type)
  rescue Nodo::Error, Shrine::FileNotFound => e
    errors.add(:score, "can't be read (#{e.message})")
  end

private

  SCORE_NOTE_SETTINGS = %i[range_start_tick range_end_tick tracks muted_tracks solo_tracks track_volumes track_tunings].freeze

  # Clears the saved ranges and track settings, which are specific to the old score
  def clear_note_score_settings
    SCORE_NOTE_SETTINGS.map { notes.where.not(it => nil) }.reduce(:or)
      .update_all(SCORE_NOTE_SETTINGS.index_with(nil).merge(updated_at: Time.current))
  end

  # (with a relation, since the association's delete_all would nullify their song, and leave it loaded)
  def delete_alternate_tabs
    AlternateTab.where(song_id: id).delete_all
  end

  # The slug's text (see `friendly_id`)
  def title_and_artist
    [title, artist].compact_blank.join(' ')
  end
end
