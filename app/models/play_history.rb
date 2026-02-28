# frozen_string_literal: true

class PlayHistory < ApplicationRecord
  belongs_to :user, required: true
  belongs_to :song, required: true

  field :date, type: Date, required: true
  field :duration, type: Float, required: true, default: 0

  index %i(user_id song_id date)
end
