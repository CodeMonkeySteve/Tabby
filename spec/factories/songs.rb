# frozen_string_literal: true

FactoryBot.define do
  factory :song do
    title { "Practice Etude" }
    artist { "Tabby" }
    score { upload_fixture('Practice Etude.gp', 'audio/x-gtp') }
    sync_points { [] }
  end

  trait :with_audio do
    audio { upload_fixture('empty.mp3', 'audio/mpeg') }
  end
end
