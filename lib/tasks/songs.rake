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
end
