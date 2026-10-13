# frozen_string_literal: true

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

    playlist.include_song!(songs.second, included: false)
    expect(playlist.ordered_songs).to eq [songs.first, songs.third]
  end

  it "finds the songs before and after a song" do
    playlist.include_song!(songs.third)
    expect(playlist.neighbors_of(songs.first)).to eq [nil, songs.second]
    expect(playlist.neighbors_of(songs.second)).to eq [songs.first, songs.third]
    expect(playlist.neighbors_of(songs.third)).to eq [songs.second, nil]
    expect(playlist.neighbors_of(create(:song))).to eq [nil, nil]
  end

  it "has a slug unique to its user, kept in its history when renamed" do
    playlist.update!(name: "Rock 'n' Roll")
    expect(playlist.slug).to eq 'rock-n-roll'
    expect(create(:playlist, user:, name: "Rock 'n' Roll").slug).to eq 'rock-n-roll-2'
    expect(create(:playlist, user: create(:user), name: "Rock 'n' Roll").slug).to eq 'rock-n-roll'
    expect(create(:playlist, user:, name: "New").slug).not_to eq 'new'

    playlist.update!(name: "Blues")
    expect(user.playlists.friendly.find('rock-n-roll')).to eq playlist
    expect(Playlist.friendly.find('blues')).to eq playlist
  end

  it "removes destroyed songs" do
    songs.first.destroy
    expect(playlist.reload.song_ids).to eq [songs.second.id]
  end
end
