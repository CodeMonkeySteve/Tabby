# frozen_string_literal: true

require 'zlib'

module Songsterr
  class Client
    VIDEO_POINTS_URL = 'https://www.songsterr.com/api/video-points/%<song_id>d/%<revision_id>d/list'
    GZIP_MAGIC = "\x1F\x8B".b

    def initialize(page)
      @page = page
    end

    def track(part_id)
      url = "https://#{@page.cloudfront_host}/#{@page.song_id}/#{@page.revision_id}/#{@page.image}/#{part_id}.json"
      parse_json(gunzip(Songsterr.get(url)), url)
    end

    def tracks
      @page.tracks.map { track(it.fetch('partId')) }
    end

    def video_points(video_id)
      url = format(VIDEO_POINTS_URL, song_id: @page.song_id, revision_id: @page.revision_id)
      video = parse_json(Songsterr.get(url), url).find { it['videoId'] == video_id }
      video or raise Error, "No sync points found for video #{video_id}"
      video.fetch('points')
    end

    private

    # CloudFront serves track JSON gzip-compressed; depending on the HTTP adapter it may already be decoded
    def gunzip(body)
      body.b.start_with?(GZIP_MAGIC) ? Zlib.gunzip(body) : body
    end

    def parse_json(body, url)
      JSON.parse(body)
    rescue JSON::ParserError => ex
      raise Error, "Invalid JSON from #{url}: #{ex.message}"
    end
  end
end
