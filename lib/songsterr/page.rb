# frozen_string_literal: true

module Songsterr
  # A Songsterr tab page, e.g. https://www.songsterr.com/a/wsa/pearl-jam-wma-bass-tab-s2687597
  class Page
    STATE_SELECTOR = 'script#state[type="application/json"]'
    DEFAULT_CLOUDFRONT_HOST = 'dqsljvtekg760.cloudfront.net'

    attr_reader :url, :metadata

    def self.fetch(url)
      new(Songsterr.get(url), url:)
    end

    def initialize(html, url: nil)
      @url = url
      @doc = Nokogiri::HTML(html)
      state = @doc.at_css(STATE_SELECTOR)
      @metadata = state && JSON.parse(state.content).dig('meta', 'current')
      @metadata or raise Error, "No song data found on Songsterr page #{url}"
    rescue JSON::ParserError => ex
      raise Error, "Invalid song data on Songsterr page #{url}: #{ex.message}"
    end

    def song_id = metadata.fetch('songId')
    def revision_id = metadata.fetch('revisionId')
    def image = metadata.fetch('image')
    def title = metadata['title']
    def artist = metadata['artist']
    def tags = metadata['tags'] || []
    def tracks = metadata['tracks'] || []
    def videos = metadata['videos'] || []

    # The synced video of the original recording (as opposed to 'alternative', 'solo', or 'backing' videos)
    def original_video_id
      videos.find { it['feature'].nil? && it['status'] == 'done' }&.fetch('videoId')
    end

    def cloudfront_host
      hosts = @doc.css('link[rel="dns-prefetch"]').map { it['href'].to_s.delete_prefix('//').delete_suffix('/') }
      hosts.find { it.end_with?('.cloudfront.net') } || DEFAULT_CLOUDFRONT_HOST
    end
  end
end
