class Song < ApplicationRecord
  include NoBrainer::Document::Timestamps
  include Song::Jellyfin

  slug_from :title, :artist

  field :title,       type: String, required: true
  field :artist,      type: String
  field :instruments, type: Array.of(String) #, required: true
  field :tempo,       type: Numeric

  include ApplicationUploader::Attachment(:score)
  field :score_data, type: Hash, required: true

  include ApplicationUploader::Attachment(:audio)
  field :audio_data, type: Hash
  field :sync_points, type: Array

  include ImageUploader::Attachment(:cover)
  field :cover_data, type: Hash

  def self.normalize_instruments(names)
    names.filter_map do |name|
      case name
        when /\bbass\b/i then 'bass'
        when /^pista\b/i then nil
        else name
      end
    end
  end
end
