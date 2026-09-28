# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SongNote do
  let(:user) { create(:user) }
  let(:song) { create(:song, track_types: %w[bass]) }

  it "is the current user's note on a song" do
    other_note = create(:song_note, song:, speed: 0.5)
    Current.user = user
    expect(song.note).to be_nil

    note = song.build_note
    expect(note).to have_attributes(user:, song:)
    note.update!(speed: 0.8, looping: true, range_start_tick: 0, range_end_tick: 3840)
    expect(song.reload.note).to eq note
    expect(song.notes).to contain_exactly note, other_note
    expect(note.playback).to eq(
      'speed' => 0.8, 'looping' => true, 'count_in' => nil, 'metronome' => nil, 'range_start_tick' => 0, 'range_end_tick' => 3840,
    )
  ensure
    Current.reset
  end

  it "clears saved ranges when the song's score changes" do
    notes = create_list(:song_note, 2, song:, speed: 0.5, range_start_tick: 0, range_end_tick: 960)
    song.update!(title: "New Title")
    expect(notes.map { it.reload.range_end_tick }).to eq [960, 960]

    song.update!(score: upload_fixture('Tears for Fears - Head Over Heels.gpx', 'audio/x-gtp'))
    expect(notes.map { it.reload.slice(:speed, :range_start_tick, :range_end_tick) })
      .to all(eq('speed' => 0.5, 'range_start_tick' => nil, 'range_end_tick' => nil))
  end

  def error_attributes(note) = note.tap(&:valid?).errors.attribute_names

  it "validates the player settings" do
    expect(error_attributes(build(:song_note, speed: 5, range_start_tick: 100, range_end_tick: 50))).to eq %i[speed range_end_tick]
    expect(error_attributes(build(:song_note, range_end_tick: 50))).to eq %i[range_end_tick]
    expect(build(:song_note, speed: 0.5, range_start_tick: 0, range_end_tick: 50)).to be_valid
  end

  it "is unique per user and song" do
    note = create(:song_note)
    expect(error_attributes(build(:song_note, user: note.user, song: note.song))).to eq %i[song_id]
  end
end
