# frozen_string_literal: true

require 'songsterr'
require 'alpha_tab'

module Song::Songsterr
  extend ActiveSupport::Concern

  module ClassMethods
    # Builds (without saving) a Song from a Songsterr tab page URL, with score, audio, and sync points.  Audio and sync points come
    # from the original recording's video when possible, otherwise from an alternative upload of the recording.  Yields progress
    # messages.  Raises Songsterr::Error, leaving the database untouched, if the score or a usable recording can't be imported.
    def from_songsterr(url, &log)
      log ||= proc { }

      page = ::Songsterr::Page.fetch(url)
      video_ids = page.recording_video_ids.presence or
        raise ::Songsterr::Error, "#{page.artist} - #{page.title} has no original or alternative recording video"

      log.("Downloading #{page.tracks.size} tracks")
      client = ::Songsterr::Client.new(page)
      parts = client.tracks
      log.("Converting score")
      result = begin
        AlphaTab.new.songsterr_to_gp(page.metadata, parts)
      rescue Nodo::Error => ex
        raise ::Songsterr::Error, "Failed to convert score: #{ex.message}"
      end
      result['warnings'].each { log.("Warning: unmapped Songsterr data #{it}") }

      Dir.mktmpdir('songsterr') do |dir|
        sync_points, audio_path = download_recording(client, video_ids, result['playedBars'], dir, log)
        score_path = Pathname(dir).join("#{page.artist} - #{page.title}.gp".tr('/', '-'))
        score_path.binwrite(result['gp'].unpack1('m'))

        song = find_by(songsterr_id: page.song_id) || find_by(title: page.title, artist: page.artist) || new
        song.assign_attributes(
          songsterr_id: page.song_id,
          title: page.title,
          artist: page.artist,
          tempo: parts.first&.dig('automations', 'tempo', 0, 'bpm'),
          track_types: page.tracks.map { songsterr_track_type(it) },
          sync_points:,
        )
        score_path.open('rb') { song.score = it }
        audio_path.open('rb') { song.audio = it }

        fetch_cover_art(song, log) unless song.cover
        song
      end
    end

    private

    # The instrument type of a Songsterr track, whose vocal, bass, and drums flags are more reliable than its name and program
    # (e.g. vocal parts are written with sax or clarinet sounds)
    def songsterr_track_type(track)
      return :vocals if track['isVocalTrack']
      return :bass if track['isBassGuitar']

      Song::Track.new(name: track['title'], program: track['instrumentId'], percussion: track['isDrums'],
                      strings: track['tuning']&.size).instrument_type
    end

    # Returns the sync points and downloaded audio of the first video that has both, checking each video's sync points before
    # downloading its audio
    def download_recording(client, video_ids, played_bars, dir, log)
      failures = video_ids.map do |video_id|
        log.("Fetching sync points for YouTube video #{video_id}")
        sync_warnings = []
        sync_points = ::Songsterr::SyncPoints.build(client.video_points(video_id), played_bars) { sync_warnings << it }

        log.("Downloading audio from YouTube video #{video_id}")
        audio_path = ::Songsterr::YouTube.download_audio(video_id, dir)
        sync_warnings.each { log.("Warning: #{it}") }
        return [sync_points, audio_path]
      rescue ::Songsterr::Error => ex
        log.("Warning: Can't use YouTube video #{video_id}: #{ex.message}")
        "#{video_id}: #{ex.message}"
      end

      raise ::Songsterr::Error, "No usable recording video:\n#{failures.join("\n")}"
    end

    # Attaches the song's cover art if it can be found, since the import doesn't depend on it
    def fetch_cover_art(song, log)
      log.("Searching for cover art")
      if (match = song.fetch_cover_art)
        log.("Found cover art for #{match.album} on #{match.source}")
      else
        log.("Warning: No cover art found")
      end
    rescue ::CoverArt::Error => ex
      log.("Warning: Can't fetch cover art: #{ex.message}")
    end
  end
end
