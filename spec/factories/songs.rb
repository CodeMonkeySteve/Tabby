# frozen_string_literal: true

FactoryBot.define do
  factory :song do
    title { "Head Over Heels" }
    artist { "Tears for Fears" }
    score { upload_fixture('Tears for Fears - Head Over Heels.gpx', 'audio/x-gtp') }
    sync_points { [] }
  end

  trait :with_audio do
    audio { upload_fixture('empty.mp3', 'audio/mpeg') }
  end
end
