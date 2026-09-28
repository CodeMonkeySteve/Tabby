# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DashboardsController do
  render_views

  let(:user) { create(:user, instrument_types: %w[bass]) }
  let(:song) { create(:song, title: "Bass Song", track_types: %w[bass]) }
  before { sign_in user }

  it "#show" do
    create(:playlist, user:, name: "Warmups", songs: [song])
    create(:play_history, user:, song:, date: Date.current, duration: 600)

    get :show
    expect(response).to be_successful
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('#playlists .accordion-button').text).to include "Warmups"
    expect(page.css('.activity-week')).to have(Dashboard::ACTIVITY_WEEKS).items
    expect(page.css('.activity-grid .activity-day.level-2')).to have(1).item
    expect(page.css('.list-group-item').map(&:text).join).to include "Bass Song"
  end

  it "#show without any data" do
    get :show
    expect(response).to be_successful
    expect(response.body).to include "No playlists yet"
  end
end
