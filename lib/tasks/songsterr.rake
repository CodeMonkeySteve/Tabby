# frozen_string_literal: true

namespace :songsterr do
  desc "Import a song (score, audio, and sync points) from a Songsterr tab URL"
  task :import, [:url] => :environment do |_task, args|
    require 'songsterr'

    url = args[:url] or abort "Usage: bin/rails 'songsterr:import[URL]'"
    song = Song.from_songsterr(url) { puts it }
    song.save!
    puts "Imported #{song.artist} - #{song.title}: /p/#{song.slug}"
  rescue Songsterr::Error, ActiveRecord::RecordInvalid => ex
    abort "Import failed: #{ex.message}"
  end

  desc "Fill in the Songsterr metadata of songs imported before it was recorded, without downloading their scores or audio"
  task backfill: :environment do
    sources = SongsterrSong.without_data.includes(:song).order(:id).to_a
    backfilled = 0
    sources.each_with_index do |source, index|
      sleep 1 if index.positive? # be gentle with Songsterr

      name = "#{source.song.artist} - #{source.song.title}"
      source.backfill
      source.song.save!
      backfilled += 1
      puts "#{name}: #{source.revision_id ? "revision #{source.revision_id}" : 'newer revision on Songsterr'}"
    rescue Songsterr::Error, ActiveRecord::RecordInvalid => ex
      warn "#{name}: #{ex.message}"
    end
    puts "Backfilled #{backfilled} of #{sources.size} Songsterr songs"
  end
end
