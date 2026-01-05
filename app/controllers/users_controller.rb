# frozen_string_literal: true

class UsersController < ApplicationController
  skip_before_action :authenticate_user!, only: %w(new login)

  def new
    redirect_to(root_url)  if current_user
  end

  def login
    auth = request.env['omniauth.auth']
    user = User.find_or_create_from_omniauth!(auth, current_user)
    if current_user
      redirect :back
    else
      reset_session
      sign_in user
      redirect_to '/'
    end
  end

  def logout
    reset_session
    sign_in nil
    redirect_to root_url, notice: "Logged out"
  end
end
