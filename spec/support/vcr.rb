# frozen_string_literal: true

require 'zlib'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr'
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.ignore_localhost = true
  config.default_cassette_options = { record: :new_episodes }

  config.before_record do |request|
    if (encoding = request.response.headers['Content-Encoding']) && (Array(encoding).first == 'gzip')
      request.response.body = Zlib::GzipReader.new(StringIO.new(request.response.body), encoding: 'ASCII-8BIT').read
      request.response.update_content_length_header
      request.response.headers.delete 'Content-Encoding'
    end
  end
end