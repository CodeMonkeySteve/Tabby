# frozen_string_literal: true

require 'songsterr'

# A Songsterr search result as shown in the song search, with the instrument type of each track, classified like a score's tracks
class Song::SongsterrMatch < Data.define(:song_id, :artist, :title, :track_types)
  # Songsterr pages show the track at an index given by a "t" suffix, or else the song's default track
  PAGE_URL = 'https://www.songsterr.com/a/wsa/%<slug>s-tab-s%<song_id>d%<track>s'

  # Songsterr's part names (track hash prefixes) that are instrument types; 'other' parts are classified by their instrument
  PART_TYPES = %w[drums bass guitar vocals].freeze

  def self.from_result(result)
    track_types = result.tracks.map do |track|
      part = track['hash'].to_s.split('_').first
      next part if PART_TYPES.include?(part)

      Song::Track.new(name: track['name'], program: track['instrumentId'], percussion: false, strings: track['tuning']&.size)
        .instrument_type.to_s
    end
    new(song_id: result.song_id, artist: result.artist, title: result.title, track_types:)
  end

  def instrument_types = Song::INSTRUMENT_TYPES.map(&:to_s) & track_types

  # The song's Songsterr page, showing the first track of an instrument type if it has one.  Songsterr redirects to its own slug
  # if this one differs.
  def url(instrument_type = nil)
    index = track_types.index(instrument_type.to_s) if instrument_type
    format(PAGE_URL, slug: "#{artist} #{title}".parameterize, song_id:, track: index ? "t#{index}" : '')
  end

  def frame_id = "songsterr_#{song_id}"
end
