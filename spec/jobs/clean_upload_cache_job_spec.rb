# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CleanUploadCacheJob do
  it "deletes cached uploads older than a week" do
    Dir.mktmpdir('upload_cache') do |dir|
      cache = UploadCache.new(Shrine::Storage::FileSystem.new(dir))
      old, recent = %w[old recent].map { Pathname(dir).join(it).tap { it.write('data') } }
      FileUtils.touch(old, mtime: 8.days.ago.to_time)
      allow(UploadCache).to receive(:new).and_return(cache)

      described_class.perform_now
      expect([old, recent].map(&:exist?)).to eq [false, true]
    end
  end
end
