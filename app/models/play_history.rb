# frozen_string_literal: true

class PlayHistory < ApplicationRecord
  belongs_to :user
  belongs_to :song

  validates :date, presence: true
  validates :duration, presence: true

  # Adds to the play duration for a user, song, and date, atomically creating the record if necessary
  def self.track!(user:, song:, date:, duration:)
    upsert(
      { user_id: user.id, song_id: song.id, date:, duration: },
      unique_by: %i[user_id song_id date],
      on_duplicate: Arel.sql('duration = play_histories.duration + excluded.duration'),
    )
  end
end
