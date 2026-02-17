# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Song, vcr: { cassette_name: 'Jellyfin' } do
  it "creates Song" do
    song = Song.create!(
      title: "Title",
      artist: "Artist",
      instruments: %w[Instrument],
      score: File.open(file_fixture_path + '/Tears for Fears - Head Over Heels.gpx'),
      audio: File.open(file_fixture_path + '/Tears for Fears - Head Over Heels.mp3'),
      sync_points: [
        {"barIndex":0,"barOccurence":0,"barPosition":0,"millisecondOffset":356},
        {"barIndex":90,"barOccurence":0,"barPosition":1,"millisecondOffset":308297}
      ],
    )

    expect(song.sync_points).to have(2).items
  end
end