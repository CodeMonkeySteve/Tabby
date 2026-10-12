# frozen_string_literal: true

FactoryBot.define do
  factory :song_note do
    user
    song
  end
end
