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

    # Synced videos of the song's recording, best first: the original, then alternatives (other uploads of the recording, as opposed
    # to 'solo' or 'backing' videos).  The same YouTube video may be listed as both, each with its own sync points.
    def recording_videos
      done = videos.select { it['status'] == 'done' }
      [*done.select { it['feature'].nil? }.first(1), *done.select { it['feature'] == 'alternative' }].uniq { it['id'] }
    end

    def recording_video_ids = recording_videos.pluck('videoId').uniq

    def cloudfront_host
      hosts = @doc.css('link[rel="dns-prefetch"]').map { it['href'].to_s.delete_prefix('//').delete_suffix('/') }
      hosts.find { it.end_with?('.cloudfront.net') } || DEFAULT_CLOUDFRONT_HOST
    end
  end
end
