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
    expect {
      attrs = attributes_for(:song).as_json
      post :create, params: { song: attrs }
    }.to change(Song, :count).by(1)
    expect(response).to redirect_to song_path(assigns(:song))
  end

  xit "#update" do
    song
    patch :update, params: { id: song, song: { title: "New title" } }
    expect(response).to have_http_status(:see_other)
    expect(song.reload.title).to eq "New title"
  end

  xit "#destroy" do
    song
    expect {
      delete :destroy, params: { id: song }
    }.to change(Song, :count).by(-1)
    expect(response).to have_http_status(:see_other)
  end

  xit "#player" do
    get :player, params: { id: song }
    expect(response).to render_template(:player)
    expect(response).to be_successful
  end

  xit "#score" do
    get :score, params: { id: song }
    expect(response).to be_successful
  end

  xit "#audio" do
    song = create(:song, :with_audio)
    get :audio, params: { id: song }
    expect(response).to be_successful
  end
end