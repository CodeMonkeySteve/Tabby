# frozen_string_literal: true

require 'omniauth/builder'
require 'omniauth-google-oauth2'

Rails.application.config.middleware.use OmniAuth::Builder do
  # update Credential#PROVIDERS enum to match
  provider :google_oauth2, *Rails.application.credentials.google.values_at(:key, :secret)
end
OmniAuth.config.allowed_request_methods = %i(post)
