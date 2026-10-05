# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UploadCache do
  around do |example|
    Dir.mktmpdir('upload_cache') do |dir|
      @dir = Pathname(dir)
      example.run
    end
  end

  let(:cache) { described_class.new(Shrine::Storage::FileSystem.new(@dir, prefix: 'files/cache')) }

  def cached_file(id, content: 'data', modified: Time.current)
    path = @dir.join('files/cache', id)
    path.dirname.mkpath
    path.write(content)
    FileUtils.touch(path, mtime: modified.to_time)
    path
  end

  it "finds and deletes only cached files older than the cutoff" do
    old = cached_file('old.gp', content: 'old score', modified: 8.days.ago)
    nested = cached_file('nested/old.mp3', modified: 30.days.ago)
    recent = cached_file('recent.gp', modified: 6.days.ago)
    stored = @dir.join('files/store.gp').tap { it.write('stored') }
    FileUtils.touch(stored, mtime: 30.days.ago.to_time)

    expect(cache.count).to eq 3
    expect(cache.expired).to eq('old.gp' => 9, 'nested/old.mp3' => 4)
    expect(cache.expired(older_than: 1.day)).to eq('old.gp' => 9, 'nested/old.mp3' => 4, 'recent.gp' => 4)
    expect(old).to exist # listing doesn't delete

    expect(cache.clean).to eq('old.gp' => 9, 'nested/old.mp3' => 4)
    expect([old, nested, recent, stored].map(&:exist?)).to eq [false, false, true, true]
    expect(nested.dirname).not_to exist # emptied directories are removed too
    expect(cache.count).to eq 1
  end

  it "finds nothing when nothing has been cached yet" do
    expect(cache.count).to eq 0
    expect(cache.clean).to eq({})
  end
end
