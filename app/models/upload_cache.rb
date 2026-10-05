# frozen_string_literal: true

# Shrine's cache of uploaded files, which keeps files that are never promoted to the store, e.g. from abandoned or invalid forms
class UploadCache
  DEFAULT_AGE = 7.days

  # The storage is a Shrine::Storage::FileSystem
  def initialize(storage = Shrine.storages[:cache])
    @storage = storage
  end

  def count = files.size

  # Sizes (in bytes) of the cached files last modified before the given age, by their IDs
  def expired(older_than: DEFAULT_AGE)
    cutoff = older_than.ago
    files.select { it.mtime < cutoff }.to_h { [id(it), it.size] }
  end

  # Deletes the expired cached files (with Shrine's FileSystem#clear!, which also removes emptied directories), returning their
  # sizes by ID (as #expired)
  def clean(older_than: DEFAULT_AGE)
    cutoff = older_than.ago
    deleted = {}
    @storage.clear! do |path|
      expired = path.mtime < cutoff
      deleted[id(path)] = path.size if expired
      expired
    end
    deleted
  end

  private

  def files = @storage.directory.glob('**/*').select(&:file?)

  def id(path) = path.relative_path_from(@storage.directory).to_s
end
