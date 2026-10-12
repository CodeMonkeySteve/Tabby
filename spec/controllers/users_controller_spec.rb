# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsersController do
  render_views

  describe "without a user" do
    it "#new" do
      get :new
      expect(response).to be_successful
      expect(response).to render_template('users/new')
    end
  end

  describe "with a logged-in user" do
    let(:user) { create(:user) }

    before { sign_in user }

    it "#new" do
      get :new
      expect(response).to redirect_to root_url
    end

    it "#edit" do
      user.update!(instrument_types: %w[bass])
      get :edit
      expect(response).to be_successful
      expect(response.body).to include 'action="/settings"'
      page = Nokogiri::HTML(response.body)
      expect(page.css('input[name="user[instrument_types][]"][type="checkbox"]').pluck('value')).to eq User::INSTRUMENT_TYPES.map(&:to_s)
      expect(page.css('input[name="user[instrument_types][]"][checked]').pluck('value')).to eq %w[bass]
    end

    describe "#update" do
      it "saves the name, email, and instruments" do
        patch :update, params: { user: { name: "New Name", email: 'new@example.com', instrument_types: ['', 'bass', 'keys'] } }
        expect(response).to redirect_to settings_path
        expect(user.reload).to have_attributes(name: "New Name", email: 'new@example.com', instrument_types: %w[bass keys])
      end

      it "clears the instruments when none are checked" do
        user.update!(instrument_types: %w[bass])
        patch :update, params: { user: { instrument_types: [''] } }
        expect(user.reload.instrument_types).to eq []
      end

      it "redisplays the form with errors" do
        patch :update, params: { user: { email: 'not an email', instrument_types: %w[other] } }
        expect(response).to have_http_status :unprocessable_content
        expect(response).to render_template :edit
        expect(assigns(:user).errors.attribute_names).to contain_exactly :email, :instrument_types
      end
    end

    describe "#dashboard" do
      let(:song) { create(:song, title: "Bass Song", track_types: %w[bass]) }

      it "#show" do
        create(:playlist, user:, name: "Warmups", songs: [song])
        create(:play_history, user:, song:, date: Date.current, duration: 600)

        get :dashboard
        expect(response).to be_successful

        page = Nokogiri::HTML(response.body)
        expect(page.at_css('#playlists .accordion-button').text).to include "Warmups"
        expect(page.css('.activity-week')).to have(Dashboard::ACTIVITY_WEEKS).items
        expect(page.css('.activity-grid .activity-day.level-2')).to have(1).item
        expect(page.css('.list-group-item').map(&:text).join).to include "Bass Song"
        expect(page.css('.list-group-item .dropdown-menu input[checked] + label').map(&:text)).to eq ["Warmups"]
        expect(page.css('.practice-summary-title').map { it.text.squish }).to eq ["This week", "Today"]
        expect(page.css('.practice-time dd').map(&:text)).to eq %w[10m 10m]
        expect(page.at_css('.practice-summary-extra a[href]')['href']).to eq player_path(song)
      end

      it "#show without any data" do
        user.update!(instrument_types: [])

        get :dashboard
        expect(response).to be_successful

        expect(response.body).to include "No playlists yet"
        expect(Nokogiri::HTML(response.body).css('.practice-summary-title').map { it.text.squish }).to eq ["This week", "Today"]
        expect(Nokogiri::HTML(response.body).at_css('a:contains("Choose your instruments")')['href']).to eq settings_path
      end
    end

    xit "#logout" do
      delete :logout
      expect(controller.current_user).to be_nil
      expect(session['user_id']).to be_nil
      expect(response).to redirect_to root_url
    end
  end
end
