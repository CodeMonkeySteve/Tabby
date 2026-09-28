# frozen_string_literal: true

require 'alpha_tab'

class Song < ApplicationRecord
  include PassiveColumns
  include Sluggable
  include Song::Jellyfin
  include Song::Songsterr

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

  # The instrument type of each score track, in track order (so not a torque-postgresql EnumSet, which is unordered and unique)
  attribute :track_types, :string, array: true, default: []

  validates :title, presence: true
  validates :score_data, presence: true
  validates :track_types, instrument_types: true

  slug_from :title, :artist

  # only needed by the player
  passive_columns :sync_points

  has_many :play_histories

  # Songs with a track for any of the given instrument types (or all songs, if none are given)
  scope :for_instruments, ->(types) { types.empty? ? all : where('track_types && ARRAY[?]::instrument_type[]', types) }

  after_destroy { Playlist.where('? = ANY(song_ids)', id).update_all(['song_ids = array_remove(song_ids, ?)', id]) }

  include ScoreUploader::Attachment(:score)
  include ApplicationUploader::Attachment(:audio)
  include ImageUploader::Attachment(:cover)

  # (Re)classify the tracks of a new score, unless their types were given with it
  before_validation :classify_tracks, if: -> { will_save_change_to_score_data? && !will_save_change_to_track_types? }

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
  rescue Nodo::Error, Shrine::FileNotFound => ex
    errors.add(:score, "can't be read (#{ex.message})")
  end
end
