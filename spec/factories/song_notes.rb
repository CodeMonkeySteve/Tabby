# frozen_string_literal: true

FactoryBot.define do
  factory :song_note do
    association :user
    association :song
  end
end
