# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScoreUploader do
  def song_with_score(extension)
    Song.new(title: "Title", score: Tempfile.new(['score', extension]))
  end

  it "accepts score formats AlphaTab can load" do
    expect(song_with_score('.gp')).to be_valid
    expect(song_with_score('.GPX')).to be_valid
    expect(song_with_score('.musicxml')).to be_valid
  end

  it "rejects other file types" do
    song = song_with_score('.mp3')
    expect(song).not_to be_valid
    expect(song.errors[:score]).to be_present
  end
end
