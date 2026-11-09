# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Song::Songsterr do
  let(:url) { 'https://www.songsterr.com/a/wsa/tabby-practice-etude-bass-tab-s1001' }
  let(:page) { Songsterr::Page.new(file_fixture('songsterr/page.html').read, url:) }
  let(:track_url) { 'https://d111111abcdef8.cloudfront.net/1001/2002/v4-1-1-PracticeEtude/%d.json' }
  let(:video_points) { JSON.parse(file_fixture('songsterr/video_points.json').read) }

  before do
    allow(Songsterr::Page).to receive(:fetch).with(url).and_return(page)
    (0..2).each do |part_id|
      stub_request(:get, format(track_url, part_id)).to_return(body: file_fixture("songsterr/#{part_id}.json.gz").binread)
    end
    stub_request(:get, 'https://www.songsterr.com/api/video-points/1001/2002/list')
      .to_return(body: ->(_request) { JSON.generate(video_points) })
    allow(Songsterr::YouTube).to receive(:download_audio) do |video_id, dir|
      Pathname(dir).join("#{video_id}.m4a").tap { FileUtils.cp(file_fixture('empty.mp3'), it) }
    end
    allow(CoverArt).to receive(:search).and_return(nil)
    # imports log their warnings and failures (and Nodo its JavaScript errors), tested below
    allow(Rails.logger).to receive_messages(warn: nil, error: nil)
  end

  it "attaches cover art when it can be found, and imports without it when it can't" do
    match = CoverArt::Match.new(source: :deezer, artist: "Tabby", title: "Practice Etude", album: "Etudes",
                                image_url: 'https://cdn.example/etudes.jpg')
    allow(CoverArt).to receive(:search).with(artist: "Tabby", title: "Practice Etude").and_return(match)
    stub_request(:get, match.image_url).to_return(body: file_fixture('cover.jpg').binread)
    messages = []
    song = Song.from_songsterr(url) { messages << it }
    song.save!

    expect(song.reload.cover).to have_attributes(original_filename: "Tabby - Etudes.jpg", mime_type: 'image/jpeg')
    expect(messages).to include("Found cover art for Etudes on deezer")

    song.update!(cover: nil)
    allow(CoverArt).to receive(:search).and_raise(CoverArt::Error, "Failed to fetch")
    messages.clear
    expect(Song.from_songsterr(url) { messages << it }).to be_valid
    expect(messages).to include("Warning: Can't fetch cover art: Failed to fetch")
  end

  it "imports score, audio, and sync points" do
    messages = []
    song = Song.from_songsterr(url) { messages << it }
    song.save!

    expect(song.reload).to have_attributes(
      title: "Practice Etude", artist: "Tabby", tempo: 96, track_types: %w[guitar bass drums],
      genres: %w[etude exercise practice],
    )
    expect(song.songsterr_song).to have_attributes(id: 1001, revision_id: 2002, recording_video_id: 'EtudeOrigin')
    expect(song.songsterr_song.page).to include('aiGenerated' => true, 'author' => include('name' => 'etude-transcriber'))
    expect(song.songsterr_song.page.keys).not_to include 'songId', 'revisionId'
    expect(song.songsterr_song.parts).to have(3).items
    expect(song.songsterr_song.parts.flat_map(&:keys)).to include('tuning', 'volume', 'automations')
    expect(song.songsterr_song.parts.flat_map(&:keys)).not_to include 'measures', 'newLyrics'
    expect(song.score.original_filename).to eq "Tabby - Practice Etude.gp"
    expect(song.audio).to be_present
    expect(song.sync_points).to have(24).items
    expect(song.sync_points.second).to include('barIndex' => 1, 'barOccurence' => 0, 'millisecondOffset' => 2500)
    expect(Songsterr::YouTube).to have_received(:download_audio).with('EtudeOrigin', anything)
    expect(messages).to include(/Downloading audio/)
  end

  it "logs its messages, and why it failed, to the Rails log" do
    allow(Rails.logger).to receive_messages(info: nil, warn: nil, error: nil)
    video_points.first['points'] = video_points.first['points'].first(22)
    Song.from_songsterr(url)

    expect(Rails.logger).to have_received(:info).with("Songsterr import #{url}: Converting score")
    expect(Rails.logger).to have_received(:warn).with(/\ASongsterr import #{url}: Warning: Video has 22 sync points/)

    page.metadata['videos'] = []
    expect { Song.from_songsterr(url) }.to raise_error(Songsterr::Error)
    expect(Rails.logger).to have_received(:error).with(/\ASongsterr import #{url} failed: .* has no original or alternative/)
  end

  it "classifies tracks by Songsterr's flags before their names and programs" do
    page.metadata['tracks'][0].merge!('isVocalTrack' => true, 'title' => "Lead Vocals")
    page.metadata['tracks'][1].merge!('instrumentId' => 30, 'title' => "Distortion Guitar")
    expect(Song.from_songsterr(url).track_types).to eq %w[vocals bass drums]
  end

  it "updates an existing song instead of creating a duplicate" do
    existing = create(:song, title: "Practice Etude", artist: "Tabby")
    Song.from_songsterr(url).save!
    Song.from_songsterr(url).save!

    expect(Song.count).to eq 1
    expect(existing.reload.songsterr_song.id).to eq 1001
  end

  it "replaces the Songsterr source of a song imported from another Songsterr song with the same title and artist" do
    existing = create(:song, title: "Practice Etude", artist: "Tabby", songsterr_song: build(:songsterr_song, id: 1, song: nil))
    Song.from_songsterr(url).save!

    expect(existing.reload.songsterr_song).to have_attributes(id: 1001, revision_id: 2002)
    expect(SongsterrSong.pluck(:id)).to eq [1001]
  end

  it "makes a valid score filename from names containing slashes" do
    page.metadata['artist'] = "AC/DC"
    expect(Song.from_songsterr(url).score.original_filename).to eq "AC-DC - Practice Etude.gp"
  end

  it "imports with a warning when the video's sync points are a few bars short" do
    video_points.first['points'] = video_points.first['points'].first(22)
    messages = []
    song = Song.from_songsterr(url) { messages << it }

    expect(song.sync_points).to have(22).items
    expect(messages).to include("Warning: Video has 22 sync points for 24 played bars; bars after 22 will follow the score's tempo")
  end

  it "uses the original video's sync points when the same YouTube video is also listed as an alternative" do
    page.metadata['videos'].unshift({ 'id' => 1, 'status' => 'done', 'feature' => 'alternative', 'videoId' => 'EtudeOrigin' })
    video_points.unshift(video_points.first.merge('id' => 1, 'feature' => 'alternative', 'points' => (0...12).map { it * 5.0 }))

    song = Song.from_songsterr(url)
    expect(song.songsterr_song.recording_video_id).to eq 'EtudeOrigin'
    expect(song.sync_points).to have(24).items
  end

  it "logs retried audio downloads as warnings" do
    allow(Songsterr::YouTube).to receive(:download_audio) do |video_id, dir, &block|
      block.("YouTube refused the download of #{video_id} (HTTP 403), retrying in 2s (try 2 of 4)")
      Pathname(dir).join("#{video_id}.m4a").tap { FileUtils.cp(file_fixture('empty.mp3'), it) }
    end
    messages = []
    Song.from_songsterr(url) { messages << it }

    expect(messages).to include("Warning: YouTube refused the download of EtudeOrigin (HTTP 403), retrying in 2s (try 2 of 4)")
  end

  describe "when the original video can't be used" do
    let(:alternative_points) { video_points.find { it['videoId'] == 'EtudeAltern' }['points'] }

    it "falls back to an alternative recording video, with its own sync points" do
      allow(Songsterr::YouTube).to receive(:download_audio).with('EtudeOrigin', anything)
                                     .and_raise(Songsterr::Error, "ERROR: [youtube] EtudeOrigin: Video unavailable")
      messages = []
      song = Song.from_songsterr(url) { messages << it }

      expect(Songsterr::YouTube).to have_received(:download_audio).with('EtudeAltern', anything)
      expect(song.audio.original_filename).to eq 'EtudeAltern.m4a'
      expect(song.sync_points.first).to include('millisecondOffset' => (alternative_points.first * 1000).round)
      expect(messages).to include("Warning: Can't use YouTube video EtudeOrigin: ERROR: [youtube] EtudeOrigin: Video unavailable")
    end

    it "skips a video whose sync points don't match the score, without downloading it" do
      video_points.first['points'] = [0, 1, 2]
      song = Song.from_songsterr(url)

      expect(Songsterr::YouTube).not_to have_received(:download_audio).with('EtudeOrigin', anything)
      expect(song.audio.original_filename).to eq 'EtudeAltern.m4a'
    end
  end

  describe "failures" do
    it "raises when there is no original or alternative recording video" do
      page.metadata['videos'] = page.videos.reject { it['feature'].nil? || it['feature'] == 'alternative' }
      expect { Song.from_songsterr(url) }.to raise_error(Songsterr::Error, /no original or alternative recording video/)
    end

    it "raises without changing anything when no video's sync points match the score" do
      existing = create(:song, title: "Practice Etude", artist: "Tabby")
      video_points.each { it['points'] = [0, 1, 2] }

      expect { Song.from_songsterr(url) }.to raise_error(Songsterr::Error, /3 sync points for 24 played bars, ending at 0:02/)
      expect(existing.reload.songsterr_song).to be_nil
      expect(Songsterr::YouTube).not_to have_received(:download_audio)
    end

    it "raises when the score can't be converted" do
      stub_request(:get, format(track_url, 0)).to_return(body: '{}')
      expect { Song.from_songsterr(url) }.to raise_error(Songsterr::Error, /Failed to convert score/)
    end

    it "raises, listing each video's problem, when no video's audio can be downloaded" do
      allow(Songsterr::YouTube).to receive(:download_audio) { |video_id| raise Songsterr::Error, "#{video_id} unavailable" }
      expect { Song.from_songsterr(url) }
        .to raise_error(Songsterr::Error, /No usable recording video.*EtudeOrigin unavailable.*EtudeAltern unavailable/m)
      expect(Song.count).to eq 0
    end
  end
end
