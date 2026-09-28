# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SongsController, vcr: { cassette_name: 'Jellyfin' }  do
  let(:user) { create(:user) }
  let(:song) { create(:song) }
  before { sign_in user }

  it "#index" do
    get :index
    expect(response).to be_successful
  end

  it "#new" do
    get :new
    expect(response).to be_successful
  end

  it "#edit" do
    get :edit, params: { id: song }
    expect(response).to be_successful
  end

  it "#create" do
    expect_any_instance_of(Song).to receive(:find_jellyfin) { [] }
    expect {
      attrs = attributes_for(:song).except(:jellyfin_id).as_json
      post :create, params: { song: attrs }
    }.to change(Song, :count).by(1)
    expect(response).to redirect_to song_path(assigns(:song))
  end

  describe "track types" do
    it "shows each track's instrument, noting overrides" do
      song.update!(track_types: %w[keys])
      get :edit, params: { id: song }
      row = Nokogiri::HTML(response.body).at_css('table[aria-labelledby="tracks-label"] tr')
      expect(row.at_css('td').text).to eq "Electric Bass"
      expect(row.at_css('select[name="song[track_types][]"] option[selected]')['value']).to eq 'keys'
      expect(row.text).to include "Detected as Bass"
    end

    it "saves overridden track types" do
      patch :update, params: { id: song, song: { title: song.title, track_types: %w[keys] } }
      expect(song.reload.track_types).to eq %w[keys]
    end

    it "saves an uploaded score" do
      score = Rack::Test::UploadedFile.new(file_fixture('Tears for Fears - Head Over Heels.gpx'), 'application/octet-stream')
      audio = Rack::Test::UploadedFile.new(file_fixture('empty.mp3'), 'audio/mpeg')
      expect {
        patch :update, params: { id: song, song: { score:, audio: } }
      }.to change { song.reload.score_data['id'] }.and change { song.reload.audio_data }.from(nil)
    end

    it "detects a new score's track types instead of the submitted ones" do
      song.update!(track_types: %w[keys])
      score = upload_fixture('Tears for Fears - Head Over Heels.gpx', 'audio/x-gtp').to_json
      patch :update, params: { id: song, song: { score:, track_types: %w[keys] } }
      expect(song.reload.track_types).to eq %w[bass]
    end
  end

  it "#update" do
    expect_any_instance_of(Song).to receive(:find_jellyfin) { [] }
    patch :update, params: { id: song, song: { title: "New title" } }
    expect(response).to have_http_status(:see_other)
    expect(song.reload.title).to eq "New title"
  end

  it "#destroy" do
    song
    expect {
      delete :destroy, params: { id: song }
    }.to change(Song, :count).by(-1)
    expect(response).to have_http_status(:see_other)
  end

  describe "#player" do
    let(:song) { create(:song, track_types: %w[guitar bass drums]) }

    def player_song
      JSON.parse(Nokogiri::HTML(response.body).at_css('[data-controller="player"]')['data-player-song-value'])
    end

    it "shows the tracks of the user's instruments" do
      user.update!(instrument_types: %w[bass drums])
      get :player, params: { id: song }
      expect(response).to render_template(:player)
      expect(response).to be_successful
      expect(player_song).to include('trackTypes' => %w[guitar bass drums], 'tracks' => [1, 2])
    end

    it "includes the user's note" do
      create(:song_note, user:, song:, speed: 0.75, looping: true)
      create(:song_note, song:, speed: 0.5)
      get :player, params: { id: song }
      expect(player_song['note']).to include('speed' => 0.75, 'looping' => true)
    end

    it "shows the default track when the user's instruments aren't in the song" do
      user.update!(instrument_types: %w[keys])
      get :player, params: { id: song }
      expect(player_song).to include('tracks' => nil)
    end
  end

  it "#score" do
    get :score, params: { id: song }
    expect(response).to be_successful
  end

  it "#audio" do
    song = create(:song, :with_audio)
    get :audio, params: { id: song }
    expect(response).to be_successful
  end

  describe "#track_history" do
    let(:play_date) { '2026-01-15' }

    it "creates a new play history record" do
      expect {
        post :track_history, params: { id: song, date: play_date, duration: '120.5' }
        expect(response).to be_successful
      }.to change(PlayHistory, :count).by(1)
    end

    it "accumulates duration for existing record on same day" do
      create(:play_history, user:, song:, date: Date.parse(play_date), duration: 60.0)
      post :track_history, params: { id: song, date: play_date, duration: '30.0' }

      expect(response).to be_successful
      expect(PlayHistory.where(user:, song:, date: Date.parse(play_date)).first.duration).to be_within(0.01).of(90.0)
    end
  end
end
