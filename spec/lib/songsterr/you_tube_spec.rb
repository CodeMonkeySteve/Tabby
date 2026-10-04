# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Songsterr::YouTube do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  def succeed_with(filename)
    FileUtils.touch(File.join(@dir, filename))
    ['', '', instance_double(Process::Status, success?: true)]
  end

  it "downloads the video's original audio stream, preferring M4A (AAC), without converting it, using Node for YouTube's JavaScript" do
    expect(Open3).to receive(:capture3) do |*args|
      expect(args).to include('yt-dlp', 'https://www.youtube.com/watch?v=K1NcoxzNgbM')
      expect(args.each_cons(2).to_a).to include(['--format', 'bestaudio[ext=m4a]/bestaudio'], ['--js-runtimes', 'node'])
      expect(args).not_to include('--extract-audio', '--audio-format')
      succeed_with('K1NcoxzNgbM.m4a')
    end

    expect(described_class.download_audio('K1NcoxzNgbM', @dir)).to eq Pathname(@dir).join('K1NcoxzNgbM.m4a')
  end

  it "returns whatever format the best audio stream is in when there's no M4A" do
    allow(Open3).to receive(:capture3) { succeed_with('K1NcoxzNgbM.webm') }
    expect(described_class.download_audio('K1NcoxzNgbM', @dir)).to eq Pathname(@dir).join('K1NcoxzNgbM.webm')
  end

  it "raises with yt-dlp's errors (not its warnings) when the download fails" do
    err = "WARNING: [youtube] No supported JavaScript runtime could be found.\nERROR: [youtube] K1NcoxzNgbM: Video unavailable\n"
    allow(Open3).to receive(:capture3).and_return(['', err, instance_double(Process::Status, success?: false)])
    expect { described_class.download_audio('K1NcoxzNgbM', @dir) }.to raise_error(Songsterr::Error) { |error|
      expect(error.message).to end_with ": ERROR: [youtube] K1NcoxzNgbM: Video unavailable"
    }
  end

  it "raises with all of yt-dlp's output when it has no errors" do
    allow(Open3).to receive(:capture3).and_return(['', "Killed\n", instance_double(Process::Status, success?: false)])
    expect { described_class.download_audio('K1NcoxzNgbM', @dir) }.to raise_error(Songsterr::Error, /: Killed\z/)
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
