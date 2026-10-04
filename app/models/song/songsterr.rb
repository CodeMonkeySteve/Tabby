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
      videos = page.recording_videos.presence or
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
        video_id, sync_points, audio_path = download_recording(client, videos, result['playedBars'], dir, log)
        score_path = Pathname(dir).join("#{page.artist} - #{page.title}.gp".tr('/', '-'))
        score_path.binwrite(result['gp'].unpack1('m'))

        source = SongsterrSong.find_by(id: page.song_id)
        song = source&.song || find_by(title: page.title, artist: page.artist) || new
        # a song matched by title and artist may have been imported from another Songsterr song, which this replaces
        source ||= song.songsterr_song || song.build_songsterr_song
        source.assign_attributes(id: page.song_id, revision_id: page.revision_id,
                                 data: SongsterrSong.data_from(page, parts, video_id))
        song.assign_attributes(
          title: page.title,
          artist: page.artist,
          tempo: source.tempo,
          genres: source.tags,
          track_types: source.track_types,
          sync_points:,
        )
        score_path.open('rb') { song.score = it }
        audio_path.open('rb') { song.audio = it }

        fetch_cover_art(song, log) unless song.cover
        song
      end
    end

    # The library's songs for Song::SongsterrMatches, by Songsterr song ID: those imported from them, or else with the same title
    # and artist (ignoring case), which importing would replace
    def for_songsterr_matches(matches)
      songs = left_joins(:songsterr_song).preload(:songsterr_song)
      songs = songs.where(songsterr_song: { id: matches.map(&:song_id) })
        .or(songs.where('LOWER(title) IN (?)', matches.map { it.title.downcase }))
        .to_a
      matches.to_h do |match|
        song = songs.find { it.songsterr_song&.id == match.song_id } ||
               songs.find { it.title.casecmp?(match.title) && it.artist.to_s.casecmp?(match.artist) }
        [match.song_id, song]
      end.compact
    end

    private

    # Returns the ID, sync points, and downloaded audio of the first video that has both, checking each video's sync points before
    # downloading its audio
    def download_recording(client, videos, played_bars, dir, log)
      failures = videos.map do |video|
        video_id = video.fetch('videoId')
        log.("Fetching sync points for YouTube video #{video_id}")
        sync_warnings = []
        sync_points = ::Songsterr::SyncPoints.build(client.video_points(video), played_bars) { sync_warnings << it }

        log.("Downloading audio from YouTube video #{video_id}")
        audio_path = ::Songsterr::YouTube.download_audio(video_id, dir)
        sync_warnings.each { log.("Warning: #{it}") }
        return [video_id, sync_points, audio_path]
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
