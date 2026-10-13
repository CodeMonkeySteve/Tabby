# frozen_string_literal: true

require 'songsterr'

# The Songsterr source of an imported song, identified by its Songsterr song ID.  `data` holds what Songsterr says about the
# song other than its score (which is converted to the song's score file), so that Song's attributes derived from it can be
# recalculated:
#
# * `page`: the tab page's metadata (Songsterr::Page#metadata), other than the song and revision IDs
# * `parts`: each track's part (Songsterr::Client#tracks), other than its measures and lyrics
# * `recordingVideoId`: the YouTube video the song's audio and sync points came from
#
# Songs imported before this was recorded have no revision ID or data, until they're backfilled (see #backfill).
class SongsterrSong < ApplicationRecord
  # Part keys that are score details, or redundant with the page
  PART_SCORE_KEYS = %w[measures newLyrics songId revisionId].freeze

  belongs_to :song

  # Songs imported before their data was recorded
  scope :without_data, ->{ where(data: {}) }

  # Builds the data from a Songsterr page, its tracks' parts, and the video used for the recording
  def self.data_from(page, parts, recording_video_id)
    {
      page: page.metadata.except('songId', 'revisionId'),
      parts: parts.map { it.except(*PART_SCORE_KEYS) },
      recordingVideoId: recording_video_id,
    }
  end

  def page = data['page'] || {}
  def parts = data['parts'] || []
  def recording_video_id = data['recordingVideoId']

  def tags = page['tags'] || []

  # The song's Songsterr tab page.  Songsterr redirects to its own slug if this one differs.
  def url = Song::SongsterrMatch.new(song_id: id, artist: song.artist, title: song.title, track_types: []).url

  # The initial tempo of the score
  def tempo = parts.first&.dig('automations', 'tempo', 0, 'bpm')

  # The instrument type of each track, from Songsterr's vocal, bass, and drums flags, which are more reliable than its name and
  # program (e.g. vocal parts are written with sax or clarinet sounds)
  def track_types
    (page['tracks'] || []).map do |track|
      next 'vocals' if track['isVocalTrack']
      next 'bass' if track['isBassGuitar']

      Song::Track.new(name: track['title'], program: track['instrumentId'], percussion: track['isDrums'],
                      strings: track['tuning']&.size).instrument_type.to_s
    end
  end

  # Fills in the data of a song imported before it was recorded, from Songsterr's current revision of the song, without
  # downloading its score or audio.  The revision ID is only recorded if the revision predates the song's score, since the import
  # used the latest revision at the time.  Also fills in the song's genres, if it has none.  Raises Songsterr::Error if the page
  # or its tracks can't be fetched.
  def backfill
    page = ::Songsterr::Page.fetch(url)
    page.song_id == id or raise ::Songsterr::Error, "#{url} is Songsterr song #{page.song_id}, not #{id}"

    self.data = self.class.data_from(page, ::Songsterr::Client.new(page).tracks, recording_video_id_from(page))
    self.revision_id = page.revision_id if Time.zone.parse(page.metadata.fetch('createdAt')) <= score_uploaded_at
    song.genres = tags if song.genres.empty?
  end

private

  # The video of the song's audio, named after its YouTube video ID by the import, if it's one of the page's recording videos
  def recording_video_id_from(page)
    video_id = song.audio && File.basename(song.audio.original_filename.to_s, '.*')
    video_id if page.recording_video_ids.include?(video_id)
  end

  # When the song's score was last stored, which is when it was imported: the score file's modification time, if it's stored in
  # the file system, or else (or if the file is missing) when the song was created
  def score_uploaded_at
    storage = song.score&.storage
    path = storage.path(song.score.id) if storage.respond_to?(:path)
    path&.exist? ? path.mtime : song.created_at
  end
end
