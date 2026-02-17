FactoryBot.define do
  factory :song do
    title { "Head Over Heels" }
    artist { "Tears for Fears" }
    instruments { %w[bass] }
    jellyfin_id { '' }
    score { upload_fixture('Tears for Fears - Head Over Heels.gpx', 'audio/x-gtp') }
    sync_points { [] }
  end

  trait :with_audio do
    audio { upload_fixture('Tears for Fears - Head Over Heels.mp3', 'audio/mpeg') }
  end
end
