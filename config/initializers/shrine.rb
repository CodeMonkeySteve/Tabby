require 'shrine'
require 'shrine/storage/file_system'

# should match static routes
storage_dir = Rails.root.join('storage').to_s
Shrine.storages = {
  cache: Shrine::Storage::FileSystem.new(storage_dir, prefix: 'files/cache'),
  store: Shrine::Storage::FileSystem.new(storage_dir, prefix: 'files'),
}

Shrine.plugin :activerecord
Shrine.plugin :cached_attachment_data   # for retaining the cached file across form redisplays
Shrine.plugin :restore_cached_data      # re-extract metadata when attaching a cached file
Shrine.plugin :determine_mime_type, analyzer: :marcel
Shrine.plugin :validation_helpers
