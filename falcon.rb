#!/usr/bin/env -S falcon host
# frozen_string_literal: true

require 'falcon/environment/rack'
require_relative 'lib/solid_queue_service'

hostname = File.basename(__dir__)
port = ENV.fetch('PORT', 3000).to_i

service hostname do
  include Falcon::Environment::Rack

  append preload 'preload.rb'
  endpoint Async::HTTP::Endpoint.parse("http://0.0.0.0:#{port}")
end

# Solid Queue's jobs, in one process; only in production, as development uses the :async adapter
if ENV['RAILS_ENV'] == 'production'
  service "#{hostname}-jobs" do
    include Async::Service::Managed::Environment

    service_class SolidQueueService
    count 1
    append preload 'preload.rb'
  end
end
