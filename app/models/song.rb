class Song < ApplicationRecord
  include NoBrainer::Document::Timestamps

  field :title, type: String, required: true
  field :artist, type: String
  field :instruments, type: Array.of(String)

  include ApplicationUploader::Attachment(:score)
  field :score_data, type: Hash, required: true

  include ApplicationUploader::Attachment(:audio)
  field :audio_data, type: Hash, required: true

  field :sync_points, type: Array

def sync_points = []
end
