# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'nokogiri'

module Songsterr
  class Error < StandardError; end

  USER_AGENT = 'Mozilla/5.0'
  OPEN_TIMEOUT = 10 # seconds
  TIMEOUT = 60

  def self.get(url)
    http.get(url).body
  rescue Faraday::Error => e
    raise Error, "Failed to fetch #{url}: #{e.message}"
  end

  def self.http
    @http ||= Faraday.new(headers: { 'User-Agent' => USER_AGENT }, request: { open_timeout: OPEN_TIMEOUT, timeout: TIMEOUT }) do |faraday|
      faraday.response :raise_error
      faraday.response :follow_redirects
    end
  end
end

require 'songsterr/page'
require 'songsterr/client'
require 'songsterr/search'
require 'songsterr/sync_points'
require 'songsterr/you_tube'
