# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Song do
  it "creates" do
    song = Song.create!(
      title: "Title",
      artist: "Artist",
      score: File.open(file_fixture_path + '/Tears for Fears - Head Over Heels.gpx'),
      audio: File.open(file_fixture_path + '/Tears for Fears - Head Over Heels.mp3'),
    )

    pp song
  end
end