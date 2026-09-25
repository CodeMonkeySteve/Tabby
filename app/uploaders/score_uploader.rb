# frozen_string_literal: true

class ScoreUploader < ApplicationUploader
  # Score formats AlphaTab's ScoreLoader can import
  ALLOWED_EXTENSIONS = %w[gp gp3 gp4 gp5 gpx musicxml mxl xml capx alphatex].freeze

  Attacher.validate do
    validate_extension ALLOWED_EXTENSIONS
  end
end
