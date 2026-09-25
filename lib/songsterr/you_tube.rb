# frozen_string_literal: true

require 'open3'

module Songsterr
  module YouTube
    extend self

    def download_audio(video_id, dir)
      url = "https://www.youtube.com/watch?v=#{video_id}"
      begin
        _out, err, status = Open3.capture3(
          'yt-dlp', '--quiet', '--no-playlist', '--extract-audio', '--audio-format', 'mp3',
          '--output', File.join(dir, '%(id)s.%(ext)s'), url
        )
      rescue Errno::ENOENT
        raise Error, "yt-dlp is not installed"
      end

      path = Pathname(dir).join("#{video_id}.mp3")
      unless status.success? && path.exist?
        raise Error, "yt-dlp failed to download audio from #{url}: #{err.strip}"
      end
      path
    end
  end
end
