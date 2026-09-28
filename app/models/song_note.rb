# frozen_string_literal: true

# A user's own data for a song, starting with their player settings
class SongNote < ApplicationRecord
  PLAYBACK_ATTRIBUTES = %i[speed looping count_in metronome range_start_tick range_end_tick].freeze

  belongs_to :user
  belongs_to :song

  validates :song_id, uniqueness: { scope: :user_id }
  validates :speed, numericality: { in: 0.25..4 }, allow_nil: true
  validates :range_start_tick, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :range_end_tick, numericality: { only_integer: true, greater_than: :range_start_tick }, if: :range_start_tick
  validates :range_end_tick, absence: true, unless: :range_start_tick

  # The player settings, for the player page
  def playback
    slice(*PLAYBACK_ATTRIBUTES)
  end
end
