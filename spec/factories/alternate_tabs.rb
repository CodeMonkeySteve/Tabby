# frozen_string_literal: true

FactoryBot.define do
  factory :alternate_tab do
    association :user
    association :song
    track_index { 0 }
    tuning { [43, 38, 33, 28] }
    note_count { 477 } # the notes of the fixture score's bass track
    strings { {} }
  end
end
