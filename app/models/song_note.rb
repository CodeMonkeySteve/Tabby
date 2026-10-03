# frozen_string_literal: true

# A user's own data for a song, starting with their player settings
class SongNote < ApplicationRecord
  PLAYBACK_ATTRIBUTES = %i[
    speed volume looping count_in metronome range_start_tick range_end_tick tracks muted_tracks solo_tracks track_volumes
    track_tunings
  ].freeze
  TRACK_LISTS = %i[tracks muted_tracks solo_tracks].freeze
  TRACK_VOLUMES = 0..16

  belongs_to :user
  belongs_to :song

  validates :song_id, uniqueness: { scope: :user_id }
  validates :speed, numericality: { in: 0.25..4 }, allow_nil: true
  validates :volume, numericality: { only_integer: true, in: 0..100 }, allow_nil: true
  validates :tracks, length: { minimum: 1 }, allow_nil: true
  validate  :track_lists_are_indexes
  validate  :track_volumes_are_volumes, if: :track_volumes
  validate  :track_tunings_are_tunings, if: :track_tunings
  validates :range_start_tick, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :range_end_tick, numericality: { only_integer: true, greater_than: :range_start_tick }, if: :range_start_tick
  validates :range_end_tick, absence: true, unless: :range_start_tick

  # The player settings, for the player page
  def playback
    slice(*PLAYBACK_ATTRIBUTES)
  end

private

  def track_lists_are_indexes
    TRACK_LISTS.each do |attribute|
      errors.add(attribute, :invalid) unless Array(self[attribute]).all? { track_index?(it) }
    end
  end

  def track_volumes_are_volumes
    valid = track_volumes.is_a?(Hash) && track_volumes.all? do |index, volume|
      track_index?(index) && volume.is_a?(Integer) && TRACK_VOLUMES.include?(volume)
    end
    errors.add(:track_volumes, :invalid) unless valid
  end

  def track_tunings_are_tunings
    valid = track_tunings.is_a?(Hash) && track_tunings.all? do |index, tuning|
      track_index?(index) && AlternateTab.tuning?(tuning)
    end
    errors.add(:track_tunings, :invalid) unless valid
  end

  def track_index?(value) = Integer(value, exception: false)&.>=(0)
end
