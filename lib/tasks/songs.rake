# frozen_string_literal: true

namespace :songs do
  desc "Reclassify every song's score tracks by instrument type (e.g. after importing, or improving Song::Track)"
  task classify_tracks: :environment do
    changed = failed = 0
    Song.find_each do |song|
      song.classify_tracks
      if song.errors.any?
        failed += 1
        warn "#{song.artist} - #{song.title}: #{song.errors.full_messages.to_sentence}"
      elsif song.track_types_changed?
        changed += 1
        song.update_columns(track_types: song.track_types)
      end
    end
    puts "#{changed} of #{Song.count} songs reclassified, #{failed} failed"
  end

  desc "Fetch cover art for songs without covers from online music catalogs"
  task covers: :environment do
    songs = Song.where(cover_data: nil).order(:artist, :title).to_a
    found = 0
    songs.each_with_index do |song, index|
      sleep 3 if index.positive? # stay within iTunes' rate limit of about 20 requests per minute

      if (match = song.fetch_cover_art)
        song.save!
        found += 1
        puts "#{song.artist} - #{song.title}: #{match.album} (#{match.source})"
      else
        warn "#{song.artist} - #{song.title}: not found"
      end
    rescue CoverArt::Error, ActiveRecord::RecordInvalid => e
      warn "#{song.artist} - #{song.title}: #{e.message}"
    end
    puts "Found covers for #{found} of #{songs.size} songs"
  end
end
