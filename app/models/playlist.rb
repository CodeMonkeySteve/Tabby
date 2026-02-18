class Playlist < ApplicationRecord
  include NoBrainer::Document::Timestamps

  belongs_to :user

  field :name, type: String, required: true

  references_many :songs, default: []
end
