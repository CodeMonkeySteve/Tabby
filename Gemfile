source 'https://rubygems.org'
ruby file: '.ruby-version'

gem 'benchmark'
gem 'ostruct'
gem 'mutex_m'

# core
gem 'rails'
gem 'kreds'
gem 'falcon'
gem 'bootsnap', require: false
gem 'lograge'
gem 'solid_cable'

# database
gem 'pg'
gem 'online_migrations'
gem 'torque-postgresql'
gem 'passive_columns'
gem 'activerecord_cursor_paginate'
gem 'email_validator'
gem 'normalizr'
gem 'rethinkdb', require: false  # for `rethinkdb:import`, remove once migrated

# file attachments
gem 'shrine'
gem 'marcel'
gem 'fastimage'

# authentication / authorization
gem 'omniauth-google-oauth2', github: 'zquestz/omniauth-google-oauth2'  # https://github.com/zquestz/omniauth-google-oauth2/pull/464
gem 'omniauth-rails_csrf_protection'
gem 'cancancan'

# assets
gem 'importmap-rails'
gem 'turbo-rails'
gem 'stimulus-rails'
gem 'haml-rails'
gem 'sass-rails'
gem 'bootstrap'
gem 'terser'
# gem 'turbo-rails'
# gem 'turbo_power'

# import
gem 'nodo'
gem 'faraday-follow_redirects'

group :development, :test do
  gem 'awesome_print'
  gem 'bundler-audit', require: false
  gem 'brakeman', require: false
end

group :test do
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rails-controller-testing'
  gem 'rspec-collection_matchers'
  gem 'rspec-rails'

  # gem 'timecop'
  gem 'webmock', require: nil
  gem 'vcr'
end
