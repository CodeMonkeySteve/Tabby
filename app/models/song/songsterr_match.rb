# frozen_string_literal: true

require 'songsterr'

# A Songsterr search result as shown in the song search, with its instrument types classified like a score's tracks
class Song::SongsterrMatch < Data.define(:song_id, :artist, :title, :instrument_types)
  PAGE_URL = 'https://www.songsterr.com/a/wsa/%<slug>s-tab-s%<song_id>d'

  # Songsterr's part names (track hash prefixes) that are instrument types; 'other' parts are classified by their instrument
  PART_TYPES = %w[drums bass guitar vocals].freeze

  def self.from_result(result)
    types = result.tracks.map do |track|
      part = track['hash'].to_s.split('_').first
      next part if PART_TYPES.include?(part)

      Song::Track.new(name: track['name'], program: track['instrumentId'], percussion: false, strings: track['tuning']&.size)
        .instrument_type.to_s
    end
    new(song_id: result.song_id, artist: result.artist, title: result.title,
        instrument_types: Song::INSTRUMENT_TYPES.map(&:to_s) & types)
  end

  # The song's Songsterr page.  Songsterr redirects to its own slug if this one differs.
  def url = format(PAGE_URL, slug: "#{artist} #{title}".parameterize, song_id:)

  def frame_id = "songsterr_#{song_id}"
end
