FactoryBot.define do
  factory :song do
    title { "Head Over Heels" }
    artist { "Tears for Fears" }
    instruments { %w[bass] }
    score { Rails.root.join('spec/fixtures/Tears for Fears - Head Over Heels.gpx').open }
    audio { Rails.root.join('spec/fixtures/Tears for Fears - Head Over Heels.mp3').open }
    sync_points { [] }
  end
end
