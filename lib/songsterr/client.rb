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

    # The sync points of one of the page's videos, matched by Songsterr ID since a YouTube video can be listed more than once (e.g.
    # as both the original and an alternative), synced separately
    def video_points(video)
      points = all_video_points.find { it['id'] == video.fetch('id') }
      points or raise Error, "No sync points found for video #{video['videoId']}"
      points.fetch('points')
    end

    private

    # Every video's points come in one list, which an import may search for several videos
    def all_video_points
      @all_video_points ||= begin
        url = format(VIDEO_POINTS_URL, song_id: @page.song_id, revision_id: @page.revision_id)
        parse_json(Songsterr.get(url), url)
      end
    end

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
