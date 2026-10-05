# frozen_string_literal: true

# Deletes old cached uploads (never promoted to the store); scheduled in config/recurring.yml
class CleanUploadCacheJob < ApplicationJob
  def perform
    expired = UploadCache.new.clean
    size = ActiveSupport::NumberHelper.number_to_human_size(expired.values.sum)
    logger.info("Deleted #{expired.size} cached uploads (#{size}) older than #{UploadCache::DEFAULT_AGE.inspect}")
  end
end
