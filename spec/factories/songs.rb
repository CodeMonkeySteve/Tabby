FactoryBot.define do
  factory :song do
    title { "Head Over Heels" }
    artist { "Tears for Fears" }
    instruments { %w[bass] }
    score { upload_fixture('Tears for Fears - Head Over Heels.gpx', 'audio/x-gtp') }
    audio { upload_fixture('Tears for Fears - Head Over Heels.mp3', 'audio/mpeg') }
    sync_points { [] }
  end
end
