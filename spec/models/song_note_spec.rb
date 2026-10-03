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
    note.update!(speed: 0.8, volume: 70, looping: true, range_start_tick: 0, range_end_tick: 3840, tracks: [0, 2], muted_tracks: [1],
                 solo_tracks: [], track_volumes: { 0 => 12, 1 => 8 }, track_tunings: { 1 => [43, 38, 33, 28, 23] })
    expect(song.reload.note).to eq note
    expect(song.notes).to contain_exactly note, other_note
    expect(note.playback).to eq(
      'speed' => 0.8, 'volume' => 70, 'looping' => true, 'count_in' => nil, 'metronome' => nil, 'range_start_tick' => 0,
      'range_end_tick' => 3840, 'tracks' => [0, 2], 'muted_tracks' => [1], 'solo_tracks' => [], 'track_volumes' => { '0' => 12, '1' => 8 },
      'track_tunings' => { '1' => [43, 38, 33, 28, 23] },
    )
  ensure
    Current.reset
  end

  it "clears saved ranges and tracks when the song's score changes" do
    notes = [
      create(:song_note, song:, speed: 0.5, range_start_tick: 0, range_end_tick: 960, track_tunings: { 0 => [43, 38, 33, 26] }),
      create(:song_note, song:, speed: 0.5, tracks: [1]),
      create(:song_note, song:, speed: 0.5, muted_tracks: [], solo_tracks: [0], track_volumes: { 0 => 4 }),
    ]
    song.update!(title: "New Title")
    expect(notes.map { it.reload.slice(:range_end_tick, :tracks, :solo_tracks).values })
      .to eq [[960, nil, nil], [nil, [1], nil], [nil, nil, [0]]]

    song.update!(score: upload_fixture('Tears for Fears - Head Over Heels.gpx', 'audio/x-gtp'))
    expect(notes.map { it.reload.slice(:speed, *Song::SCORE_NOTE_SETTINGS) })
      .to all(eq('speed' => 0.5, **Song::SCORE_NOTE_SETTINGS.to_h { [it.to_s, nil] }))
  end

  def error_attributes(note) = note.tap(&:valid?).errors.attribute_names

  it "validates the player settings" do
    expect(error_attributes(build(:song_note, speed: 5, range_start_tick: 100, range_end_tick: 50))).to eq %i[speed range_end_tick]
    expect(error_attributes(build(:song_note, range_end_tick: 50))).to eq %i[range_end_tick]
    expect(error_attributes(build(:song_note, volume: 101, tracks: []))).to eq %i[volume tracks]
    expect(error_attributes(build(:song_note, volume: -1, tracks: [0, -1]))).to eq %i[volume tracks]
    expect(error_attributes(build(:song_note, muted_tracks: [-1], solo_tracks: [nil], track_volumes: { 0 => 17 })))
      .to eq %i[muted_tracks solo_tracks track_volumes]
    expect(error_attributes(build(:song_note, track_volumes: { 'a' => 8 }))).to eq %i[track_volumes]
    expect(error_attributes(build(:song_note, track_volumes: [8]))).to eq %i[track_volumes]
    expect(error_attributes(build(:song_note, track_tunings: { 0 => [] }))).to eq %i[track_tunings]
    expect(error_attributes(build(:song_note, track_tunings: { 0 => [128] }))).to eq %i[track_tunings]
    expect(error_attributes(build(:song_note, track_tunings: { 'a' => [40] }))).to eq %i[track_tunings]
    expect(error_attributes(build(:song_note, track_tunings: [[40]]))).to eq %i[track_tunings]
    expect(build(:song_note, speed: 0.5, volume: 0, range_start_tick: 0, range_end_tick: 50, tracks: [0, 3], muted_tracks: [],
                             solo_tracks: [1], track_volumes: { 0 => 0, 3 => 16 }, track_tunings: { 3 => [60] })).to be_valid
  end

  it "is unique per user and song" do
    note = create(:song_note)
    expect(error_attributes(build(:song_note, user: note.user, song: note.song))).to eq %i[song_id]
  end
end
