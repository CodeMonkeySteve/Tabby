# frozen_string_literal: true

FactoryBot.define do
  factory :play_history do
    user
    song
    date { Date.current }
    duration { 0.0 }
  end
end
