
Song.create!(
  title: "Head Over Heels",
  artist: "Tears For Fears",
  score: Rails.root.join('sandbox', 'Tears For Fears - Head Over Heels.gpx').open,
  audio: Rails.root.join('sandbox', 'Tears for Fears - Sowing the Seeds of Love - 17 - Head Over Heels.mp3')
)
