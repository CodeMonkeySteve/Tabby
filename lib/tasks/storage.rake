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
      puts "#{delete ? 'Deleting' : 'Unreferenced'} #{id}"
      store.delete(id) if delete
    end
    puts "#{unreferenced.size} of #{files.size} stored files (#{size}) #{delete ? 'deleted' : 'unreferenced, run with DELETE=1 to delete'}"
  end

  desc "Delete cached uploads older than DAYS (default 7) days (only lists them unless DELETE=1)"
  task clean_cache: :environment do
    cache = UploadCache.new
    older_than = ENV.fetch('DAYS', 7).to_i.days
    count = cache.count

    delete = ENV['DELETE'].to_s.to_bool
    expired = delete ? cache.clean(older_than:) : cache.expired(older_than:)
    expired.each_key { puts "#{delete ? 'Deleted' : 'Expired'} #{it}" }

    size = ActiveSupport::NumberHelper.number_to_human_size(expired.values.sum)
    puts "#{expired.size} of #{count} cached files (#{size}) older than #{older_than.ago.to_date} " \
         "#{delete ? 'deleted' : 'expired, run with DELETE=1 to delete'}"
  end
end
