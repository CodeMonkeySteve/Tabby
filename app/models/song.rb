class Song < ApplicationRecord
  include NoBrainer::Document::Timestamps

  slug_from :title, :artist

  field :title,       type: String,           required: true
  field :instruments, type: Array.of(String) #, required: true
  field :artist,      type: String

  include ApplicationUploader::Attachment(:score)
  field :score_data, type: Hash, required: true

  include ApplicationUploader::Attachment(:audio)
  field :audio_data, type: Hash
  field :sync_points, type: Array

  include ImageUploader::Attachment(:cover)
  field :cover_data, type: Hash
end
