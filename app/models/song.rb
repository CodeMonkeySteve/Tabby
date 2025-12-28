class Song < ApplicationRecord
  has_one_attached :score
  has_one_attached :audio

  validates :title, presence: true
  validates :score, presence: true

def sync_points
  []
end
end
