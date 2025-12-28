source 'https://rubygems.org'

gem 'rails', '~> 8.1.1'
gem 'sqlite3', '>= 2.1'
gem 'falcon'
gem 'bootsnap', require: false

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
  gem 'rspec'
  gem 'rspec-rails'
  gem 'rspec-collection_matchers'
end