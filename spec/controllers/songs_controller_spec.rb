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

  it "#player" do
    get :player, params: { id: song }
    expect(response).to render_template(:player)
    expect(response).to be_successful
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
