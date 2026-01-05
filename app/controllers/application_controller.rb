class ApplicationController < ActionController::Base
  include AuthenticationController
  before_action :authenticate_user!

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  protect_from_forgery with: :exception
  # rescue_from(NoBrainer::Error::DocumentNotFound) { render_not_found }
  # rescue_from(CanCan::AccessDenied) { render_access_denied, status: 401 }
end
