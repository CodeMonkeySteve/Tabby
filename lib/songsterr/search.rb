# frozen_string_literal: true

require 'cgi'

module Songsterr
  # A song found by Songsterr::Search, with its raw track descriptions (instrumentId, name, tuning, and a hash whose prefix is
  # Songsterr's guess at the part: 'guitar', 'bass', 'vocals', 'drums', or 'other')
  Result = Data.define(:song_id, :artist, :title, :tracks)

  # Songsterr's song search, as used by its site search box
  module Search
    URL = 'https://www.songsterr.com/api/songs'
    SIZE = 20

    # The matching songs, excluding those Songsterr flags as junk
    def self.call(query, size: SIZE)
      url = "#{URL}?#{URI.encode_www_form(pattern: query, size:)}"
      songs = begin
        JSON.parse(Songsterr.get(url))
      rescue JSON::ParserError => ex
        raise Error, "Invalid JSON from #{url}: #{ex.message}"
      end

      songs.reject { it['isJunk'] }.map do |song|
        # some older songs' names are HTML-encoded
        Result.new(song_id: song.fetch('songId'), artist: CGI.unescapeHTML(song['artist'].to_s),
                   title: CGI.unescapeHTML(song['title'].to_s), tracks: song['tracks'] || [])
      end
    end
  end
end
