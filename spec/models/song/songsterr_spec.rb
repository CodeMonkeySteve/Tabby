# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Song::Songsterr, clean_db: true do
  let(:url) { 'https://www.songsterr.com/a/wsa/pearl-jam-wma-bass-tab-s2687597' }
  let(:page) { Songsterr::Page.new(file_fixture('songsterr/page.html').read, url:) }
  let(:track_url) { 'https://dqsljvtekg760.cloudfront.net/2687597/3537915/v4-6-3-EAi4zBWPBvY-23HR/%d.json' }
  let(:video_points) { JSON.parse(file_fixture('songsterr/video_points.json').read) }

  before do
    allow(Songsterr::Page).to receive(:fetch).with(url).and_return(page)
    (0..2).each do |part_id|
      stub_request(:get, format(track_url, part_id)).to_return(body: file_fixture("songsterr/#{part_id}.json.gz").binread)
    end
    stub_request(:get, 'https://www.songsterr.com/api/video-points/2687597/3537915/list')
      .to_return(body: ->(_request) { JSON.generate(video_points) })
    allow(Songsterr::YouTube).to receive(:download_audio) do |video_id, dir|
      Pathname(dir).join("#{video_id}.m4a").tap { FileUtils.cp(file_fixture('empty.mp3'), it) }
    end
    allow_any_instance_of(Song).to receive(:find_jellyfin).and_return([])
  end

  it "imports score, audio, and sync points" do
    messages = []
    song = Song.from_songsterr(url) { messages << it }
    song.save!

    expect(song.reload).to have_attributes(
      songsterr_id: 2687597, title: "W.M.A.", artist: "Pearl Jam", tempo: 108,
      instruments: ["Distortion Guitar", 'bass', "Drums"], jellyfin_id: nil,
    )
    expect(song.score.original_filename).to eq "Pearl Jam - W.M.A..gp"
    expect(song.audio).to be_present
    expect(song.sync_points).to have(150).items
    expect(song.sync_points.second).to include('barIndex' => 1, 'barOccurence' => 0, 'millisecondOffset' => 2120)
    expect(Songsterr::YouTube).to have_received(:download_audio).with('K1NcoxzNgbM', anything)
    expect(messages).to include(/Downloading audio/)
  end

  it "updates an existing song instead of creating a duplicate" do
    existing = create(:song, title: "W.M.A.", artist: "Pearl Jam")
    Song.from_songsterr(url).save!
    Song.from_songsterr(url).save!

    expect(Song.count).to eq 1
    expect(existing.reload.songsterr_id).to eq 2687597
  end

  it "makes a valid score filename from names containing slashes" do
    page.metadata['artist'] = "AC/DC"
    expect(Song.from_songsterr(url).score.original_filename).to eq "AC-DC - W.M.A..gp"
  end

  it "imports with a warning when the video's sync points are a few bars short" do
    video_points.first['points'] = video_points.first['points'].first(148)
    messages = []
    song = Song.from_songsterr(url) { messages << it }

    expect(song.sync_points).to have(148).items
    expect(messages).to include("Warning: Video has 148 sync points for 150 played bars; bars after 148 will follow the score's tempo")
  end

  describe "failures" do
    it "raises when there is no original recording video" do
      page.metadata['videos'] = page.videos.reject { it['feature'].nil? }
      expect { Song.from_songsterr(url) }.to raise_error(Songsterr::Error, /no original recording/)
    end

    it "raises without changing anything when sync points don't match the score" do
      existing = create(:song, title: "W.M.A.", artist: "Pearl Jam")
      video_points.first['points'] = [0, 1, 2]

      expect { Song.from_songsterr(url) }.to raise_error(Songsterr::Error, /Sync point count/)
      expect(existing.reload.songsterr_id).to be_nil
      expect(Songsterr::YouTube).not_to have_received(:download_audio)
    end

    it "raises when the score can't be converted" do
      stub_request(:get, format(track_url, 0)).to_return(body: '{}')
      expect { Song.from_songsterr(url) }.to raise_error(Songsterr::Error, /Failed to convert score/)
    end

    it "raises when the audio download fails" do
      allow(Songsterr::YouTube).to receive(:download_audio).and_raise(Songsterr::Error, "yt-dlp failed")
      expect { Song.from_songsterr(url) }.to raise_error(Songsterr::Error, /yt-dlp failed/)
      expect(Song.count).to eq 0
    end
  end
end
