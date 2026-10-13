# frozen_string_literal: true

require 'open3'
require 'retriable'

module Songsterr
  module YouTube
    extend self

    # The original audio stream, never re-encoded. M4A (AAC) is preferred for property seeking in browser
    FORMAT = 'bestaudio[ext=m4a]/bestaudio'

    # yt-dlp needs a JavaScript runtime to extract YouTube's formats reliably, and only enables Deno by default
    JS_RUNTIME = 'node'

    # YouTube sometimes refuses a download (HTTP 403) that works when retried.  yt-dlp's own retries reuse the refused stream URL,
    # so yt-dlp is rerun to extract fresh ones, backing off exponentially (about 2, 4, then 8 seconds).
    TRIES = 4
    RETRY_ON = { Error => /HTTP Error 403/ }.freeze

    # Returns the Pathname of the downloaded audio file, in whatever format YouTube served it.  Yields a message before each retry.
    def download_audio(video_id, dir)
      on_retry = ->(_exception, try, _elapsed_time, next_interval) do
        next unless next_interval # gave up

        if block_given?
          yield "YouTube refused the download of #{video_id} (HTTP 403), retrying in #{next_interval.round}s " \
                "(try #{try + 1} of #{TRIES})"
        end
      end
      Retriable.retriable(on: RETRY_ON, tries: TRIES, base_interval: 2, multiplier: 2, on_retry:) { download(video_id, dir) }
    end

  private

    def download(video_id, dir)
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
