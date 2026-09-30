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

  def edit
    @user = current_user
  end

  def update
    @user = current_user
    if @user.update(user_params)
      redirect_to settings_path, notice: "Settings were successfully saved.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def dashboard
    @dashboard = Dashboard.new(current_user)
  end

private

  def user_params
    # drops the blank value collection_check_boxes submits so that every instrument can be unchecked
    params.require(:user).permit(:name, :email, instrument_types: [])
      .tap { it[:instrument_types]&.compact_blank! }
  end
end
