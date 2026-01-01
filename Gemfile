source 'https://rubygems.org'

# core
gem 'rails', '~> 8.1.1'
gem 'falcon'
gem 'bootsnap', require: false

# storage
gem 'nobrainer', github: 'CodeMonkeySteve/nobrainer', branch: 'rails-8.1'
  #, branch: 'main'    # https://github.com/NoBrainerORM/nobrainer/pull/292
gem 'nobrainer-references'
gem 'normalizr'
gem 'shrine'

# assets
gem 'propshaft'
gem 'cssbundling-rails'
gem 'jsbundling-rails'
gem 'haml-rails'
gem 'turbo-rails'
gem 'stimulus-rails'
gem 'jbuilder'

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem 'bcrypt', '~> 3.1.7'

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
# gem 'solid_cache'
# gem 'solid_queue'
# gem 'solid_cable'

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem 'image_processing', '~> 1.2'

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