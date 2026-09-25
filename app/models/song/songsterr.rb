# frozen_string_literal: true

require 'songsterr'
require 'alpha_tab'

module Song::Songsterr
  extend ActiveSupport::Concern

  included do
    field :songsterr_id, type: Integer, index: true
  end

  module ClassMethods
    # Builds (without saving) a Song from a Songsterr tab page URL, with score, audio, and sync points.  Yields progress
    # messages.  Raises Songsterr::Error, leaving the database untouched, if any of the score, audio, or sync points can't be
    # imported.
    def from_songsterr(url, &log)
      log ||= proc { }

      page = ::Songsterr::Page.fetch(url)
      video_id = page.original_video_id or
        raise ::Songsterr::Error, "#{page.artist} - #{page.title} has no original recording video"

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

      log.("Fetching sync points")
      sync_points = ::Songsterr::SyncPoints.build(client.video_points(video_id), result['playedBars'])

      Dir.mktmpdir('songsterr') do |dir|
        log.("Downloading audio from YouTube video #{video_id}")
        audio_path = ::Songsterr::YouTube.download_audio(video_id, dir)
        score_path = Pathname(dir).join("#{page.artist} - #{page.title}.gp".tr('/', '-'))
        score_path.binwrite(result['gp'].unpack1('m'))

        song = where(songsterr_id: page.song_id).first || where(title: page.title, artist: page.artist).first || new
        song.assign_attributes(
          songsterr_id: page.song_id,
          title: page.title,
          artist: page.artist,
          tempo: parts.first&.dig('automations', 'tempo', 0, 'bpm'),
          instruments: normalize_instruments(page.tracks.pluck('instrument')).uniq,
          sync_points:,
        )
        score_path.open('rb') { song.score = it }
        audio_path.open('rb') { song.audio = it }

        if song.cover.nil? && (item = song.find_jellyfin.first) && (cover = song.jellyfin_cover(item))
          song.cover = cover
        end
        song
      end
    end
  end
end
