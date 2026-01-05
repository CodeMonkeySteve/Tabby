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

    xit "#logout" do
      get :logout
      expect(controller.current_user).to be_nil
      expect(session['user_id']).to be_nil
      expect(response).to redirect_to root_url
    end
  end
end
