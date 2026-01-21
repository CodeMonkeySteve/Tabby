require 'shrine'
require 'shrine/storage/file_system'

# should match static routes
Shrine.storages = {
  cache: Shrine::Storage::FileSystem.new('storage', prefix: 'files/cache'),
  store: Shrine::Storage::FileSystem.new('storage', prefix: 'files'),
}

Shrine.plugin :nobrainer
Shrine.plugin :cached_attachment_data   # for retaining the cached file across form redisplays
Shrine.plugin :restore_cached_data      # re-extract metadata when attaching a cached file
Shrine.plugin :determine_mime_type, analyzer: :fastimage
Shrine.plugin :store_dimensions, analyzer: :fastimage
