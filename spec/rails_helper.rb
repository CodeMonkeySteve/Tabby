# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require 'spec_helper'
require File.expand_path("../../config/environment", __FILE__)
abort("The Rails environment is running in production mode!") if Rails.env.production?

require 'rspec/rails'
require 'faker'
#require 'timecop'

RSpec.configure do |config|
  config.file_fixture_path = "#{::Rails.root}/spec/fixtures"
  config.infer_spec_type_from_file_location!
  config.use_transactional_fixtures = true
  config.infer_base_class_for_anonymous_controllers = false
  config.render_views = true
end

Dir[Rails.root.join('spec/support/**/*.rb')].each { |f| require(f) }
