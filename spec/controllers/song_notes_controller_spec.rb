# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SongNotesController do
  let(:user) { create(:user) }
  let(:song) { create(:song, track_types: %w[bass]) }
  let(:playback) do
    { speed: 0.7, volume: 80, looping: true, count_in: false, metronome: true, range_start_tick: 960, range_end_tick: 7680, tracks: [1, 2],
      muted_tracks: [2], solo_tracks: [], track_volumes: { '1' => 10, '2' => 8 }, track_tunings: { '1' => [43, 38, 33, 28, 23] } }
  end
  before { sign_in user }

  def note_for(user) = SongNote.find_by(user:, song:)

  it "creates the user's note" do
    patch :update, params: { song_id: song, song_note: playback }, as: :json
    expect(response).to have_http_status :no_content
    expect(note_for(user).playback.symbolize_keys).to eq playback
  end

  it "updates the user's note without touching others'" do
    other_note = create(:song_note, song:, speed: 0.5)
    create(:song_note, user:, song:, speed: 0.5, range_start_tick: 0, range_end_tick: 960)

    patch :update, params: { song_id: song, song_note: playback.merge(range_start_tick: nil, range_end_tick: nil, tracks: nil) }, as: :json
    expect(note_for(user)).to have_attributes(speed: 0.7, range_start_tick: nil, range_end_tick: nil, tracks: nil)
    expect(other_note.reload.speed).to eq 0.5
    expect(SongNote.count).to eq 2
  end

  it "rejects invalid settings" do
    patch :update, params: { song_id: song, song_note: { speed: 10 } }, as: :json
    expect(response).to have_http_status :unprocessable_entity
    expect(response.parsed_body).to include 'speed'
    expect(note_for(user)).to be_nil
  end
end
