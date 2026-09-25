# frozen_string_literal: true

require 'faraday'
require 'nokogiri'

module Songsterr
  class Error < StandardError; end

  USER_AGENT = 'Mozilla/5.0'

  def self.get(url)
    http.get(url).body
  rescue Faraday::Error => ex
    raise Error, "Failed to fetch #{url}: #{ex.message}"
  end

  def self.http
    @http ||= Faraday.new(headers: { 'User-Agent' => USER_AGENT }) do |faraday|
      faraday.response :raise_error
    end
  end
end

require 'songsterr/page'
require 'songsterr/client'
require 'songsterr/sync_points'
require 'songsterr/you_tube'
