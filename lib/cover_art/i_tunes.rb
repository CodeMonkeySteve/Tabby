# frozen_string_literal: true

# https://performance-partners.apple.com/search-api (limited to about 20 requests per minute)
module CoverArt::ITunes
  SEARCH_URL = 'https://itunes.apple.com/search'
  LIMIT = 25
  IMAGE_SIZE = '1000x1000bb'

  # Matches for the songs found by a free-text query, with their artwork URLs rewritten from thumbnails to 1000x1000 images
  def self.search(query)
    response = CoverArt.get_json(SEARCH_URL, term: query, entity: 'song', limit: LIMIT)

    response['results'].filter_map do |track|
      thumbnail = track['artworkUrl100'].presence or next

      CoverArt::Match.new(source: :itunes, artist: track['artistName'], title: track['trackName'], album: track['collectionName'],
                          image_url: thumbnail.sub(%r{/\d+x\d+bb\.}, "/#{IMAGE_SIZE}."))
    end
  end
end
