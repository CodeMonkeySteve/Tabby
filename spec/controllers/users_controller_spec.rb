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
        expect(response).to have_http_status :unprocessable_entity
        expect(response).to render_template :edit
        expect(assigns(:user).errors.attribute_names).to contain_exactly :email, :instrument_types
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
