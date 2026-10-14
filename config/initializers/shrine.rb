# frozen_string_literal: true

require 'shrine'
require 'shrine/storage/file_system'

# Set before any uploader is loaded (e.g. by eager loading), since a Shrine subclass copies its parent's storages when defined
Shrine.storages =
  if Rails.env.test?
    require 'shrine/storage/memory'
    { cache: Shrine::Storage::Memory.new, store: Shrine::Storage::Memory.new }
  else
    # should match static routes
    storage_dir = Rails.root.join('storage').to_s
    {
      cache: Shrine::Storage::FileSystem.new(storage_dir, prefix: 'files/cache'),
      store: Shrine::Storage::FileSystem.new(storage_dir, prefix: 'files'),
    }
  end

Shrine.plugin :activerecord
Shrine.plugin :cached_attachment_data   # for retaining the cached file across form redisplays
Shrine.plugin :restore_cached_data      # re-extract metadata when attaching a cached file
Shrine.plugin :determine_mime_type, analyzer: :marcel
Shrine.plugin :validation_helpers
