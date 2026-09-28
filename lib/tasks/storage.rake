# frozen_string_literal: true

namespace :storage do
  desc "Delete stored files that no song references (only lists them unless DELETE=1)"
  task clean: :environment do
    Song.any? or abort "There are no songs, so every stored file would be deleted"

    store, cache = Shrine.storages.values_at(:store, :cache)
    attachments = Song.pluck(:score_data, :audio_data, :cover_data).flatten.compact
    referenced = attachments.filter_map { it['id'] if it['storage'] == 'store' }.to_set

    # the cache is a subdirectory of the store
    files = store.directory.glob('**/*').select(&:file?).reject { it.to_s.start_with?("#{cache.directory}/") }
    unreferenced = files.index_by { it.relative_path_from(store.directory).to_s }.except(*referenced)
    size = ActiveSupport::NumberHelper.number_to_human_size(unreferenced.values.sum(&:size))

    missing = referenced.count { !store.exists?(it) }
    warn "Warning: #{missing} referenced files are missing from #{store.directory}" if missing.positive?

    delete = ENV['DELETE'].to_s.to_bool
    unreferenced.each_key do |id|
      puts "#{delete ? "Deleting" : "Unreferenced"} #{id}"
      store.delete(id) if delete
    end
    puts "#{unreferenced.size} of #{files.size} stored files (#{size}) #{delete ? "deleted" : "unreferenced, run with DELETE=1 to delete"}"
  end

  desc "Delete cached uploads older than DAYS (default 7) days (only lists them unless DELETE=1)"
  task clean_cache: :environment do
    cache = Shrine.storages[:cache]
    cutoff = ENV.fetch('DAYS', 7).to_i.days.ago

    files = cache.directory.glob('**/*').select(&:file?)
    expired = files.select { it.mtime < cutoff }.index_by { it.relative_path_from(cache.directory).to_s }
    size = ActiveSupport::NumberHelper.number_to_human_size(expired.values.sum(&:size))

    delete = ENV['DELETE'].to_s.to_bool
    expired.each_key do |id|
      puts "#{delete ? "Deleting" : "Expired"} #{id}"
      cache.delete(id) if delete
    end
    puts "#{expired.size} of #{files.size} cached files (#{size}) older than #{cutoff.to_date} " \
      "#{delete ? "deleted" : "expired, run with DELETE=1 to delete"}"
  end
end
