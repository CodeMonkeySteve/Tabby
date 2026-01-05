Song.create!(
  title: "Head Over Heels",
  artist: "Tears For Fears",
  instruments: %w[bass],
  score: Rails.root.join('spec/fixtures', 'Tears for Fears - Head Over Heels.gpx').open,
  audio: Rails.root.join('spec/fixtures', 'Tears for Fears - Head Over Heels.mp3').open,
)
