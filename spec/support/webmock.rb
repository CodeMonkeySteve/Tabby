# frozen_string_literal: true

require 'webmock/rspec'

RSpec.configure do |config|
  config.before { |_example| WebMock.reset! }
end

# https://github.com/vcr/vcr/issues/615
require 'webmock/http_lib_adapters/async_http_client_adapter'
module WebMockExt
  def build_response(...)
    super.tap do |response|
      # remove encoding headers (body has no encoding)
      response.headers.extract %w[transfer-encoding content-encoding]
    end
  end
end
Async::HTTP::WebMockApplication.singleton_class.prepend WebMockExt
