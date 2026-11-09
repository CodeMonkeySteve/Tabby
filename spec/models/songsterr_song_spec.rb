# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SongsterrSong do
  it "derives song attributes from Songsterr's flags, ahead of track names and programs" do
    songsterr_song = described_class.new(data: {
      page: {
        tags: %w[rock],
        tracks: [
          { title: "Lead Vocals", instrumentId: 65, isVocalTrack: true },
          { title: "Distortion Guitar", instrumentId: 30, isBassGuitar: true, tuning: [43, 38, 33, 28] },
          { title: "Drums", instrumentId: 1024, isDrums: true },
          { title: "Rhythm", instrumentId: 30, tuning: [64, 59, 55, 50, 45, 40] },
        ],
      },
      parts: [{ automations: { tempo: [{ measure: 0, bpm: 96 }] } }],
    }.deep_stringify_keys)

    expect(songsterr_song).to have_attributes(tags: %w[rock], tempo: 96, track_types: %w[vocals bass drums guitar])
  end

  it "has no derived attributes without data" do
    expect(described_class.new).to have_attributes(tags: [], tempo: nil, track_types: [], recording_video_id: nil)
  end

  describe "#backfill" do
    let(:page) { Songsterr::Page.new(file_fixture('songsterr/page.html').read) }
    let(:track_url) { 'https://d111111abcdef8.cloudfront.net/1001/2002/v4-1-1-PracticeEtude/%d.json' }
    let(:audio) { upload_fixture('empty.mp3', 'audio/mpeg').tap { it.metadata['filename'] = 'EtudeOrigin.m4a' } }
    let(:song) { create(:song, title: "Practice Etude", artist: "Tabby", audio:) }
    let(:songsterr_song) { create(:songsterr_song, id: 1001, song:) }

    before do
      allow(Songsterr::Page).to receive(:fetch).with('https://www.songsterr.com/a/wsa/tabby-practice-etude-tab-s1001')
                                  .and_return(page)
      (0..2).each do |part_id|
        stub_request(:get, format(track_url, part_id)).to_return(body: file_fixture("songsterr/#{part_id}.json.gz").binread)
      end
    end

    it "fills in the data, revision, and song genres from the current revision, which predates the score" do
      songsterr_song.backfill
      song.save!

      expect(songsterr_song.reload).to have_attributes(revision_id: 2002, recording_video_id: 'EtudeOrigin', tempo: 96,
                                                       track_types: %w[guitar bass drums])
      expect(songsterr_song.parts).to have(3).items
      expect(song.reload.genres).to include 'etude'
      expect(described_class.without_data).to be_empty
    end

    it "leaves the revision unknown when the current revision is newer than the score, and keeps existing genres" do
      page.metadata['createdAt'] = 1.minute.from_now.iso8601
      song.update!(genres: %w[seattle])
      songsterr_song.backfill
      song.save!

      expect(songsterr_song.reload).to have_attributes(revision_id: nil, tempo: 96)
      expect(song.reload.genres).to eq %w[seattle]
    end

    it "omits the recording video when the song's audio isn't from one of the page's videos, and raises for the wrong song" do
      audio.metadata['filename'] = 'other.mp3'
      songsterr_song.backfill
      expect(songsterr_song.recording_video_id).to be_nil

      page.metadata['songId'] = 1
      expect { songsterr_song.backfill }.to raise_error(Songsterr::Error, /is Songsterr song 1, not 1001/)
    end
  end
end
