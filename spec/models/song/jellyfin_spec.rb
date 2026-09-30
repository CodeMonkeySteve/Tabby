# frozen_string_literal: true

require 'rails_helper'

RSpec.xdescribe Song::Jellyfin do
  describe '#jellyfin_cover' do
    let(:song) { Song.new }

    it "returns the item's primary image" do
      item = Jellyfin::Item.new('Id' => 'song', 'ImageTags' => { 'Primary' => 'tag' })
      allow(item).to receive(:get).with('Images/Primary', hash_including(tag: 'tag')).and_return(double(body: 'song image'))
      expect(song.jellyfin_cover(item).read).to eq 'song image'
    end

    it "falls back to the album's primary image" do
      item = Jellyfin::Item.new('Id' => 'song', 'ImageTags' => {}, 'AlbumId' => 'album', 'AlbumPrimaryImageTag' => 'tag')
      allow_any_instance_of(Jellyfin::Item).to receive(:get) do |album, *args|
        expect([album.id, args.first]).to eq ['album', 'Images/Primary']
        double(body: 'album image')
      end
      expect(song.jellyfin_cover(item).read).to eq 'album image'
    end

    it "returns nil without an image" do
      expect(song.jellyfin_cover(Jellyfin::Item.new('Id' => 'song', 'ImageTags' => {}))).to be_nil
    end
  end
end
