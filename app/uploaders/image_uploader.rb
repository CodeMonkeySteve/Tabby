class ImageUploader < ApplicationUploader
  ALLOWED_TYPES  = %w[image/jpeg image/png image/webp].freeze
  MAX_SIZE       = 10.megabytes
  MAX_DIMENSIONS = [5_000, 5_000]

  plugin :store_dimensions, analyzer: :fastimage
  plugin :remove_attachment

  Attacher.validate do
    validate_size 0..MAX_SIZE
    if validate_mime_type ALLOWED_TYPES
      validate_max_dimensions MAX_DIMENSIONS
    end
  end
end
