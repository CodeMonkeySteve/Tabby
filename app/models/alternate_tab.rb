# frozen_string_literal: true

# A user's own fingering of a score track's notes, in a tuning (the score's own, or another).  It holds the string of each note
# played on a different string than in the score, by the note's index in the track (see app/javascript/lib/track_tab.js); frets
# follow from the notes' pitches.
class AlternateTab < ApplicationRecord
  MIDI_NOTES = 0..127

  belongs_to :user
  belongs_to :song

  validates :track_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate  :tuning_is_tuning
  validates :note_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate  :strings_are_note_strings

  # Whether a value is a tuning: MIDI notes, at least one
  def self.tuning?(value) = value.is_a?(Array) && value.present? && value.all? { it.is_a?(Integer) && MIDI_NOTES.include?(it) }

  # Tabs in exactly the tuning (since `where(tuning:)` would match any of its values)
  scope :in_tuning, ->(tuning) { where('tuning = ARRAY[?]::integer[]', tuning) }

  # Merges string changes by note index (nil restores the score's string) in one statement, so concurrent changes aren't lost,
  # unless any is invalid
  def merge_strings(changes)
    unless changes.is_a?(Hash) && changes.all? { |index, string| note_index?(index) && (!string || note_string?(string)) }
      errors.add(:strings, :invalid)
      return false
    end

    self.class.where(id:)
      .update_all(['strings = jsonb_strip_nulls(strings || ?::jsonb), updated_at = ?', changes.to_json, Time.current])
    reload
    true
  end

  # The attributes the player uses
  def for_player
    { id:, trackIndex: track_index, tuning:, noteCount: note_count, strings:, optimizer: }
  end

private

  def tuning_is_tuning
    errors.add(:tuning, :invalid) unless self.class.tuning?(tuning)
  end

  def strings_are_note_strings
    valid = strings.is_a?(Hash) && strings.all? { |index, string| note_index?(index) && note_string?(string) }
    errors.add(:strings, :invalid) unless valid
  end

  def note_index?(value) = value.to_s.match?(/\A\d+\z/) && value.to_i < note_count.to_i

  def note_string?(value) = value.is_a?(Integer) && value.between?(1, Array(tuning).length)
end
