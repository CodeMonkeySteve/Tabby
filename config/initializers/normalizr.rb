# frozen_string_literal: true

Normalizr.configure do |config|
  default :strip, :blank
  # config.normalizers[:boolean] = ->(value, _options) { value.to_bool }
end
