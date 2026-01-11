source 'https://rubygems.org'

# core
gem 'rails', '~> 8.1.1'
gem 'falcon'
gem 'bootsnap', require: false

# gem 'solid_cache'
# gem 'solid_queue'
# gem 'solid_cable'

# storage
gem 'nobrainer', github: 'CodeMonkeySteve/nobrainer', branch: 'rails-8.1'
  #, branch: 'main'    # https://github.com/NoBrainerORM/nobrainer/pull/292
gem 'nobrainer-references'
gem 'normalizr'
gem 'shrine'

# authentication / authorization
gem 'omniauth-google-oauth2', github: 'zquestz/omniauth-google-oauth2'  # https://github.com/zquestz/omniauth-google-oauth2/pull/464
gem 'omniauth-rails_csrf_protection'
gem 'cancancan'

# assets
gem 'propshaft'
gem 'dartsass-rails'
gem 'jsbundling-rails'
gem 'haml-rails'
gem 'turbo-rails'
gem 'jbuilder'

gem 'bootstrap'
gem 'stimulus-rails'
gem 'simple_form'

gem 'marcel'

group :development do
  gem 'web-console'
end

group :development, :test do
  gem 'bundler-audit', require: false
  gem 'brakeman', require: false
  gem 'rubocop-rails-omakase', require: false
end

group :test do
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rails-controller-testing'
  gem 'rspec-rails'
  gem 'rspec-collection_matchers'

  # gem 'timecop'
  # gem 'webmock', require: nil
  # gem 'vcr'
end