# frozen_string_literal: true

module Jellyfin
  extend self

  class Item
    attr_reader :id, :attributes
    delegate_missing_to :attributes

    def initialize(attributes = {})
      @id = attributes['Id']
      @attributes = attributes
    end

    def get(sub_path, params = {})
      path = "/Items/#{id}"
      path += "/#{sub_path}"  if sub_path
      Jellyfin.api.get(path, params)
    end
  end

  def items(**params)
    api.get('Items', params.compact).body['Items'].map { |item| Item.new(item) }
  end

  def api
    @api ||= Faraday.new(
      url: Kreds.fetch!(:jellyfin, :url),
      request: { params_encoder: Faraday::FlatParamsEncoder },
      ssl: { verify: false }
    ) do |faraday|
      faraday.adapter Faraday.default_adapter
      token = Kreds.fetch!(:jellyfin, :access_token)
      faraday.headers['Authorization'] = "MediaBrowser Client=\"Tabby\",Token=\"#{token}\""
      faraday.response :json, content_type: /\bjson$/
      # faraday.response :logger, Logger.new($stderr, level: Logger::DEBUG)
    end
  end
end

