# frozen_string_literal: true

module AuthenticationController
  extend ActiveSupport::Concern

  included do
    helper_method :current_user

    after_action do
      # belt and suspenders
      Current.user = nil
    end
  end

  def sign_in(user)
    if user
      session[:user] = user.id.to_s
    else
      session.delete(:user)
    end
    Current.user = user
  end

  def current_user
    user = Current.user
    if !user && (user_id = session[:user].presence)
      user = User.find_by(id: user_id)
      sign_in user
    end
    user
  end

  def authenticate_user!
    unless current_user
      session[:return_to] = url_for(only_path: true)
      redirect_to :login
    end
  end
end
