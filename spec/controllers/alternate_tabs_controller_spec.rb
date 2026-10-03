# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlternateTabsController do
  let(:user) { create(:user) }
  let(:song) { create(:song, track_types: %w[bass]) }
  let(:five_string) { [43, 38, 33, 28, 23] }
  before { sign_in user }

  def create_params(**attributes) = { track_index: 0, tuning: five_string, note_count: 477, **attributes }

  it "creates the user's alternate tab, or replaces it" do
    post :create, params: { song_id: song, alternate_tab: create_params(strings: { '0' => 2 }, optimizer: 'beam') }, as: :json
    expect(response).to have_http_status :created
    tab = AlternateTab.find_by!(user:, song:)
    expect(response.parsed_body).to eq('id' => tab.id)
    expect(tab).to have_attributes(track_index: 0, tuning: five_string, note_count: 477, strings: { '0' => 2 }, optimizer: 'beam')

    post :create, params: { song_id: song, alternate_tab: create_params }, as: :json
    expect(response.parsed_body).to eq('id' => tab.id)
    expect(tab.reload).to have_attributes(strings: {}, optimizer: nil)
    expect(AlternateTab.count).to eq 1
  end

  it "rejects an invalid alternate tab" do
    post :create, params: { song_id: song, alternate_tab: create_params(strings: { '0' => 6 }) }, as: :json
    expect(response).to have_http_status :unprocessable_entity
    expect(response.parsed_body).to include 'strings'
    expect(AlternateTab.count).to eq 0
  end

  it "rejects tunings that aren't MIDI notes, without retrying forever" do
    create(:alternate_tab, user:, song:, tuning: [43, 38, 33, 28])
    [[43.5, 38, 33, 28], ['abc'], [nil]].each do |tuning|
      post :create, params: { song_id: song, alternate_tab: create_params(tuning:) }, as: :json
      expect(response).to have_http_status :unprocessable_entity
      expect(response.parsed_body).to include 'tuning'
    end
    expect(AlternateTab.count).to eq 1
  end

  it "merges string changes" do
    tab = create(:alternate_tab, user:, song:, tuning: five_string, strings: { '1' => 2, '5' => 3 })
    patch :update, params: { song_id: song, id: tab, alternate_tab: { strings: { '5' => nil, '7' => 4 } } }, as: :json
    expect(response).to have_http_status :no_content
    expect(tab.reload.strings).to eq('1' => 2, '7' => 4)

    patch :update, params: { song_id: song, id: tab, alternate_tab: { strings: { '7' => 9 } } }, as: :json
    expect(response).to have_http_status :unprocessable_entity
    expect(response.parsed_body).to include 'strings'
    expect(tab.reload.strings).to eq('1' => 2, '7' => 4)
  end

  it "replaces the strings" do
    tab = create(:alternate_tab, user:, song:, tuning: five_string, strings: { '1' => 2 }, optimizer: 'beam')
    put :update, params: { song_id: song, id: tab, alternate_tab: { strings: { '3' => 1 }, optimizer: 'beam' } }, as: :json
    expect(response).to have_http_status :no_content
    expect(tab.reload).to have_attributes(strings: { '3' => 1 }, optimizer: 'beam')
  end

  it "deletes the alternate tab" do
    tab = create(:alternate_tab, user:, song:)
    delete :destroy, params: { song_id: song, id: tab }
    expect(response).to have_http_status :no_content
    expect(AlternateTab.exists?(tab.id)).to be false
  end

  it "doesn't reach another user's alternate tabs" do
    tab = create(:alternate_tab, song:)
    expect {
      patch :update, params: { song_id: song, id: tab, alternate_tab: { strings: { '1' => 2 } } }, as: :json
    }.to raise_error ActionController::RoutingError
    expect { delete :destroy, params: { song_id: song, id: tab } }.to raise_error ActionController::RoutingError

    post :create, params: { song_id: song, alternate_tab: create_params(tuning: tab.tuning) }, as: :json
    expect(AlternateTab.where(song:).count).to eq 2
    expect(tab.reload.strings).to eq({})
  end
end
