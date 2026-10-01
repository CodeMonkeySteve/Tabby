FactoryBot.define do
  factory :songsterr_song do
    sequence(:id) { 1000 + it }
    song
  end
end
