# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include AuthenticationController

  before_action :authenticate_user!

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  protect_from_forgery with: :exception

  rescue_from(ActiveRecord::RecordNotFound) do
    raise ActionController::RoutingError.new('Not Found')
  end

  # rescue_from(CanCan::AccessDenied) { render_access_denied, status: 401 }
end
