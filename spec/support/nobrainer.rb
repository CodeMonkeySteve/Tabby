# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:suite) do
    NoBrainer.purge!
    NoBrainer.sync_schema
  end

  config.before(:each, clean_db: true) do
    NoBrainer.purge!
  end
end

