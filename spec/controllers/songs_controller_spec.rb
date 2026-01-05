# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SongsController do
  let(:user) { create(:user) }
  let(:song) { create(:song) }
  before { sign_in user }

  it "#index" do
    get :index
    expect(response).to be_successful
  end

  it "#show" do
    get :show, params: { id: song }
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

  xit "#create" do
    expect {
      post :create, params: {    }
    }.to change(Song, :count).by(1)
    expect(response).to be_successful
  end

  xit "#update" do
    # ...
  end

  it "#destroy" do
    song
    expect {
      delete :destroy, params: { id: song }
    }.to change(Song, :count).by(-1)
    expect(response).to be_successful
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
    get :audio, params: { id: song }
    expect(response).to be_successful
  end
end