# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Songsterr::YouTube do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  def succeed_with(filename)
    FileUtils.touch(File.join(@dir, filename))
    ['', '', instance_double(Process::Status, success?: true)]
  end

  it "downloads the original audio stream, preferring M4A (AAC), without converting it, running YouTube's JavaScript with Node" do
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

  it "raises with yt-dlp's errors (not its warnings) when the download fails, without retrying" do
    err = "WARNING: [youtube] No supported JavaScript runtime could be found.\nERROR: [youtube] K1NcoxzNgbM: Video unavailable\n"
    allow(Open3).to receive(:capture3).and_return(['', err, instance_double(Process::Status, success?: false)])
    expect { described_class.download_audio('K1NcoxzNgbM', @dir) }.to raise_error(Songsterr::Error) { |error|
      expect(error.message).to end_with ": ERROR: [youtube] K1NcoxzNgbM: Video unavailable"
    }
    expect(Open3).to have_received(:capture3).once
  end

  describe "when YouTube refuses the download" do
    let(:forbidden) do
      ['', "ERROR: unable to download video data: HTTP Error 403: Forbidden\n", instance_double(Process::Status, success?: false)]
    end

    it "retries, yielding a message before each retry" do
      attempts = 0
      allow(Open3).to receive(:capture3) { (attempts += 1) < 3 ? forbidden : succeed_with('K1NcoxzNgbM.m4a') }
      messages = []
      expect(described_class.download_audio('K1NcoxzNgbM', @dir) { messages << it }).to eq Pathname(@dir).join('K1NcoxzNgbM.m4a')
      expect(attempts).to eq 3
      expect(messages).to match [/\AYouTube refused the download of K1NcoxzNgbM \(HTTP 403\), retrying in \d+s \(try 2 of 4\)\z/,
                                 /\(try 3 of 4\)\z/]
    end

    it "gives up after a few tries" do
      allow(Open3).to receive(:capture3).and_return(forbidden)
      messages = []
      expect { described_class.download_audio('K1NcoxzNgbM', @dir) { messages << it } }
        .to raise_error(Songsterr::Error, /HTTP Error 403/)
      expect(Open3).to have_received(:capture3).exactly(described_class::TRIES).times
      expect(messages).to have(described_class::TRIES - 1).items # none after the last try
    end
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
