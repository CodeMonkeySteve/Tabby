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
end
