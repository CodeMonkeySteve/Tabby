# frozen_string_literal: true

require 'open3'

module Songsterr
  module YouTube
    extend self

    # The original audio stream, never re-encoded. M4A (AAC) is preferred for property seeking in browser
    FORMAT = 'bestaudio[ext=m4a]/bestaudio'

    # yt-dlp needs a JavaScript runtime to extract YouTube's formats reliably, and only enables Deno by default
    JS_RUNTIME = 'node'

    # Returns the Pathname of the downloaded audio file, in whatever format YouTube served it
    def download_audio(video_id, dir)
      url = "https://www.youtube.com/watch?v=#{video_id}"
      begin
        _out, err, status = Open3.capture3(
          'yt-dlp', '--quiet', '--no-playlist', '--js-runtimes', JS_RUNTIME,
          '--format', FORMAT, '--output', File.join(dir, '%(id)s.%(ext)s'), url
        )
      rescue Errno::ENOENT
        raise Error, "yt-dlp is not installed"
      end

      path = Pathname(dir).glob("#{video_id}.*").first
      unless status.success? && path
        # yt-dlp's warnings are mostly noise here; its errors say what went wrong
        errors = err.lines.grep(/\AERROR:/).join.presence || err
        raise Error, "yt-dlp failed to download audio from #{url}: #{errors.strip}"
      end
      path
    end
  end
end
