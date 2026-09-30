# frozen_string_literal: true

# https://developers.deezer.com/api/search (its field-qualified searches, e.g. `artist:"..."`, currently return nothing)
module CoverArt::Deezer
  SEARCH_URL = 'https://api.deezer.com/search'
  LIMIT = 25

  # Matches for the tracks found by a free-text query, with 1000x1000 album covers
  def self.search(query)
    response = CoverArt.get_json(SEARCH_URL, q: query, limit: LIMIT)
    if (error = response['error'])
      raise CoverArt::Error, "Deezer search failed: #{error['message']}"
    end

    response['data'].filter_map do |track|
      album = track['album']
      next if album['md5_image'].blank? || album['cover_xl'].blank?

      CoverArt::Match.new(source: :deezer, artist: track.dig('artist', 'name'), title: track['title'], album: album['title'],
                          image_url: album['cover_xl'])
    end
  end
end
