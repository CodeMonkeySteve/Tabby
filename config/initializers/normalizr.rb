module NoBrainer::Document::ClassMethods
  include Normalizr::Concern::ClassMethods
end

Normalizr.configure do |config|
  default :strip, :blank
  # config.normalizers[:boolean] = ->(value, _options) { value.to_bool }
end
