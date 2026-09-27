require 'rails_helper'

RSpec.describe Playlist, vcr: { cassette_name: 'Jellyfin' } do
  let(:user) { create(:user) }
  let(:songs) { %w[One Two Three].map { create(:song, title: it) } }
  let!(:playlist) { create(:playlist, user:, songs: songs.first(2)) }

  it "adds and removes songs, preserving order" do
    playlist.include_song!(songs.third)
    playlist.include_song!(songs.first)
    expect(playlist.song_ids).to eq songs.map(&:id)
    expect(playlist.ordered_songs).to eq songs

    playlist.include_song!(songs.second, false)
    expect(playlist.ordered_songs).to eq [songs.first, songs.third]
  end

  it "removes destroyed songs" do
    songs.first.destroy
    expect(playlist.reload.song_ids).to eq [songs.second.id]
  end
end
