# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Song do
  it "creates Song" do
    song = Song.create!(
      title: "Title",
      artist: "Artist",
      score: file_fixture('Practice Etude.gp').open,
      audio: file_fixture('empty.mp3').open,
      sync_points: [
        { barIndex: 0, barOccurence: 0, barPosition: 0, millisecondOffset: 356 },
        { barIndex: 90, barOccurence: 0, barPosition: 1, millisecondOffset: 308297 }
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

  describe "slugs" do
    it "derives a slug from the title and artist, numbering taken slugs" do
      song = create(:song, title: "Don't Fear the Reaper's Cowbell", artist: "Blue Öyster Cult")
      expect(song.slug).to eq 'don-t-fear-the-reapers-cowbell-blue-oyster-cult'
      expect(create(:song, title: song.title, artist: song.artist).slug).to eq "#{song.slug}-2"
      expect(create(:song, title: "New", artist: nil).slug).to eq 'new-2' # not the new song page
    end

    it "keeps finding a renamed song by its old slugs, which other songs can't take" do
      song = create(:song)
      old_slug = song.slug
      song.update!(title: "Warmup")
      expect(song.slug).to eq 'warmup-tabby'
      expect(Song.friendly.find(old_slug)).to eq song
      expect(Song.friendly.find(song.id)).to eq song
      expect(create(:song).slug).to eq "#{old_slug}-2"

      song.update!(title: "Practice Etude")
      expect(song.slug).to eq old_slug
    end

    it "keeps the saved slug as its URL param until it's saved" do
      song = create(:song)
      song.title = "Warmup"
      expect(song).to be_valid
      expect(song.to_param).to eq 'practice-etude-tabby'
    end
  end

  describe "track classification" do
    let(:unreadable_score) do
      Shrine.upload(StringIO.new('not a score'), :cache, metadata: false).tap do |file|
        file.metadata.update('filename' => 'bad.gp', 'size' => 11, 'mime_type' => 'application/octet-stream')
      end
    end

    it "classifies the tracks of a new score" do
      song = create(:song, track_types: %w[guitar])
      song.update!(score: upload_fixture('Practice Etude.gp', 'audio/x-gtp'))
      expect(song.reload.track_types).to eq %w[bass]
      expect(create(:song).track_types).to eq %w[bass]
    end

    it "classifies the tracks of a MusicXML score" do
      song = create(:song, score: upload_fixture('Practice Etude.musicxml', 'application/vnd.recordare.musicxml+xml'))
      expect(song.reload.track_types).to eq %w[keys guitar]
    end

    it "finds the tracks played by instrument types" do
      song = build(:song, track_types: %w[guitar bass vocals bass])
      expect(song.track_indexes_for(%w[bass keys])).to eq [1, 3]
      expect(song.track_indexes_for(%w[keys])).to eq []
      expect(song.instrument_types).to eq %w[bass guitar vocals]
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
      allow(Nodo.logger).to receive(:error)
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

  it "searches by title and artist" do
    schism = create(:song, title: "Schism", artist: "Tool", track_types: %w[bass])
    lateralus = create(:song, title: "Lateralus", artist: "Tool", track_types: %w[bass])
    hysteria = create(:song, title: "Hysteria", artist: "Muse", track_types: %w[bass])

    expect(Song.search("tool")).to contain_exactly schism, lateralus
    expect(Song.search("SCHISM")).to contain_exactly schism
    expect(Song.search("tool lat")).to contain_exactly lateralus
    expect(Song.search("teria mus")).to contain_exactly hysteria
    expect(Song.search("100%")).to be_empty
    expect(Song.search("  ")).to contain_exactly schism, lateralus, hysteria
  end

  it "sorts by title, artist, newest, or the user's most recent play" do
    user = create(:user)
    schism = create(:song, title: "Schism", artist: "Tool", created_at: 3.days.ago)
    lateralus = create(:song, title: "Lateralus", artist: "Tool", created_at: 1.day.ago)
    hysteria = create(:song, title: "Hysteria", artist: "Muse", created_at: 2.days.ago)
    create(:play_history, user:, song: schism, date: 2.days.ago)
    create(:play_history, user:, song: schism, date: 5.days.ago)
    create(:play_history, user:, song: hysteria, date: 3.days.ago)
    create(:play_history, song: lateralus, date: Date.current) # another user's

    expect(Song.sorted(nil)).to eq [hysteria, lateralus, schism]
    expect(Song.sorted('bogus')).to eq [hysteria, lateralus, schism]
    expect(Song.sorted('artist')).to eq [hysteria, lateralus, schism]
    expect(Song.sorted('newest')).to eq [lateralus, hysteria, schism]
    expect(Song.sorted('played', user:)).to eq [schism, hysteria, lateralus]
    expect(Song.search("tool").sorted('played', user:)).to eq [schism, lateralus]
  end
end
