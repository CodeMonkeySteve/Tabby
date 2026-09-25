# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Songsterr::YouTube do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  it "downloads the video's audio as MP3 with yt-dlp" do
    expect(Open3).to receive(:capture3) do |*args|
      expect(args).to include('yt-dlp', '--extract-audio', 'https://www.youtube.com/watch?v=K1NcoxzNgbM')
      FileUtils.touch(File.join(@dir, 'K1NcoxzNgbM.mp3'))
      ['', '', instance_double(Process::Status, success?: true)]
    end

    expect(described_class.download_audio('K1NcoxzNgbM', @dir)).to eq Pathname(@dir).join('K1NcoxzNgbM.mp3')
  end

  it "raises with yt-dlp's error output when the download fails" do
    allow(Open3).to receive(:capture3).and_return(['', "ERROR: Video unavailable\n", instance_double(Process::Status, success?: false)])
    expect { described_class.download_audio('K1NcoxzNgbM', @dir) }.to raise_error(Songsterr::Error, /Video unavailable/)
  end

  it "raises when yt-dlp isn't installed" do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)
    expect { described_class.download_audio('K1NcoxzNgbM', @dir) }.to raise_error(Songsterr::Error, /yt-dlp is not installed/)
  end
end
