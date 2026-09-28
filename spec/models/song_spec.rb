# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Song, vcr: { cassette_name: 'Jellyfin' } do
  it "creates Song" do
    song = Song.create!(
      title: "Title",
      artist: "Artist",
      score: File.open(file_fixture_path + '/Tears for Fears - Head Over Heels.gpx'),
      audio: File.open(file_fixture_path + '/empty.mp3'),
      sync_points: [
        {"barIndex":0,"barOccurence":0,"barPosition":0,"millisecondOffset":356},
        {"barIndex":90,"barOccurence":0,"barPosition":1,"millisecondOffset":308297}
      ],
    )

    expect(song.sync_points).to have(2).items
  end

  it "stores the instrument type of each track, in order and with repeats" do
    song = create(:song, track_types: %i[guitar bass guitar other])
    expect(song.reload.track_types).to eq %w[guitar bass guitar other]
    expect(Song.new.track_types).to eq []
    expect(Song.where('track_types && ARRAY[?]::instrument_type[]', %w[bass keys])).to eq [song]
    expect(Song.where('track_types && ARRAY[?]::instrument_type[]', %w[keys])).to be_empty

    song.track_types = %w[bass bogus]
    expect(song).not_to be_valid
    expect(song.errors[:track_types]).to eq ["is not included in the list"]
  end

  describe "track classification" do
    let(:unreadable_score) do
      Shrine.upload(StringIO.new('not a score'), :cache, metadata: false).tap do
        it.metadata.update('filename' => 'bad.gp', 'size' => 11, 'mime_type' => 'application/octet-stream')
      end
    end

    it "classifies the tracks of a new score" do
      song = create(:song, track_types: %w[guitar])
      song.update!(score: upload_fixture('Tears for Fears - Head Over Heels.gpx', 'audio/x-gtp'))
      expect(song.reload.track_types).to eq %w[bass]
      expect(create(:song).track_types).to eq %w[bass]
    end

    it "keeps track types given with the score" do
      expect(create(:song, track_types: %w[vocals]).reload.track_types).to eq %w[vocals]
    end

    it "doesn't reclassify when the score doesn't change" do
      song = create(:song)
      song.update!(track_types: %w[keys])
      song.update!(title: "New Title")
      expect(song.reload.track_types).to eq %w[keys]
    end

    it "rejects a score AlphaTab can't read" do
      song = build(:song, score: unreadable_score)
      expect(song).not_to be_valid
      expect(song.errors[:score].sole).to start_with "can't be read"
    end

    it "reports a missing score file" do
      song = create(:song)
      song.score.delete
      song.classify_tracks
      expect(song.errors[:score].sole).to match(/can't be read .* not found/)
    end
  end
end
