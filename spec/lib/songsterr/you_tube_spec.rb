# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Songsterr::YouTube do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  def succeed_with(filename)
    FileUtils.touch(File.join(@dir, filename))
    ['', '', instance_double(Process::Status, success?: true)]
  end

  it "downloads the video's original audio stream, preferring M4A (AAC), without converting it" do
    expect(Open3).to receive(:capture3) do |*args|
      expect(args).to include('yt-dlp', 'https://www.youtube.com/watch?v=K1NcoxzNgbM')
      expect(args.each_cons(2).to_a).to include(['--format', 'bestaudio[ext=m4a]/bestaudio'])
      expect(args).not_to include('--extract-audio', '--audio-format')
      succeed_with('K1NcoxzNgbM.m4a')
    end

    expect(described_class.download_audio('K1NcoxzNgbM', @dir)).to eq Pathname(@dir).join('K1NcoxzNgbM.m4a')
  end

  it "returns whatever format the best audio stream is in when there's no M4A" do
    allow(Open3).to receive(:capture3) { succeed_with('K1NcoxzNgbM.webm') }
    expect(described_class.download_audio('K1NcoxzNgbM', @dir)).to eq Pathname(@dir).join('K1NcoxzNgbM.webm')
  end

  it "raises with yt-dlp's error output when the download fails" do
    allow(Open3).to receive(:capture3).and_return(['', "ERROR: Video unavailable\n", instance_double(Process::Status, success?: false)])
    expect { described_class.download_audio('K1NcoxzNgbM', @dir) }.to raise_error(Songsterr::Error, /Video unavailable/)
  end

  it "raises when yt-dlp succeeds without producing a file" do
    allow(Open3).to receive(:capture3).and_return(['', '', instance_double(Process::Status, success?: true)])
    expect { described_class.download_audio('K1NcoxzNgbM', @dir) }.to raise_error(Songsterr::Error, /yt-dlp failed/)
  end

  it "raises when yt-dlp isn't installed" do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)
    expect { described_class.download_audio('K1NcoxzNgbM', @dir) }.to raise_error(Songsterr::Error, /yt-dlp is not installed/)
  end
end
