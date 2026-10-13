# frozen_string_literal: true

require 'rails_helper'
require 'cover_art'

RSpec.describe CoverArt do
  def deezer_track(title, album, artist: "Tears For Fears", md5: 'abc123')
    { title:, artist: { name: artist }, album: { title: album, md5_image: md5, cover_xl: "https://cdn.example/#{album.parameterize}.jpg" } }
  end

  def itunes_track(title, album, artist: "Tears for Fears")
    { trackName: title, artistName: artist, collectionName: album,
      artworkUrl100: "https://is1-ssl.mzstatic.com/image/thumb/#{album.parameterize}/100x100bb.jpg" }
  end

  def stub_deezer(*tracks)
    stub_request(:get, CoverArt::Deezer::SEARCH_URL).with(query: hash_including(q: "Tears for Fears Head Over Heels"))
      .to_return(body: JSON.generate(data: tracks))
  end

  def stub_itunes(*tracks)
    stub_request(:get, CoverArt::ITunes::SEARCH_URL).with(query: hash_including(term: "Tears for Fears Head Over Heels", entity: 'song'))
      .to_return(body: JSON.generate(results: tracks))
  end

  describe '.search' do
    subject(:match) { described_class.search(artist: "Tears for Fears", title: "Head Over Heels") }

    it "prefers the studio album over live recordings and compilations, matching names loosely" do
      stub_deezer(
        deezer_track("Head Over Heels", "Rule The World: The Greatest Hits"),
        deezer_track("Head Over Heels (Live)", "Songs From The Big Chair"),
        deezer_track("Head Over Heels", "Tears Roll Down", artist: "Tears Four Fears"),
        deezer_track("Head Over Heels - 2014 Remaster", "Songs From The Big Chair (Deluxe)"),
      )

      expect(match).to have_attributes(source: :deezer, title: "Head Over Heels - 2014 Remaster", album: "Songs From The Big Chair (Deluxe)",
                                       image_url: 'https://cdn.example/songs-from-the-big-chair-deluxe.jpg')
    end

    it "falls back to iTunes, at full size, when Deezer has no match with cover art" do
      stub_deezer(deezer_track("Head Over Heels", "Songs From The Big Chair", md5: ''), deezer_track("Shout", "Songs From The Big Chair"))
      stub_itunes(itunes_track("Head Over Heels", "Songs from the Big Chair"))

      expect(match).to have_attributes(source: :itunes, album: "Songs from the Big Chair",
                                       image_url: 'https://is1-ssl.mzstatic.com/image/thumb/songs-from-the-big-chair/1000x1000bb.jpg')
    end

    it "returns nil when no catalog has a match, or the song has no artist" do
      stub_deezer
      stub_itunes(itunes_track("Head Over Heels", "Head Over Heels", artist: "The Go-Go's"))

      expect(match).to be_nil
      expect(described_class.search(artist: nil, title: "Head Over Heels")).to be_nil
    end

    it "raises on catalog errors" do
      stub_request(:get, CoverArt::Deezer::SEARCH_URL).with(query: hash_including({}))
        .to_return(body: JSON.generate(error: { message: "Quota limit exceeded" }))
      expect { match }.to raise_error(CoverArt::Error, "Deezer search failed: Quota limit exceeded")

      stub_request(:get, CoverArt::Deezer::SEARCH_URL).with(query: hash_including({})).to_timeout
      expect { described_class.search(artist: "Tears for Fears", title: "Head Over Heels") }.to raise_error(CoverArt::Error, /Failed to fetch/)
    end
  end

  describe '.normalize' do
    it "ignores case, punctuation, accents, a leading \"The\", and trailing version notes" do
      expect(described_class.normalize("The Beatles")).to eq described_class.normalize("Beatles")
      expect(described_class.normalize("Blue Öyster Cult")).to eq 'blueoystercult'
      expect(described_class.normalize("Simon & Garfunkel")).to eq 'simonandgarfunkel'
      expect(described_class.normalize("W.M.A. (Remastered) [Live]")).to eq 'wma'
      expect(described_class.normalize("(Don't Fear) The Reaper - Remastered 2001")).to eq 'dontfearthereaper'
      expect(described_class.normalize("Hello - Goodbye")).to eq 'hellogoodbye'
    end
  end

  describe '.download' do
    it "names the image for its album" do
      match = CoverArt::Match.new(source: :deezer, artist: "AC/DC", title: "Back in Black", album: "Back in Black",
                                  image_url: 'https://cdn.example/cover.jpg')
      stub_request(:get, match.image_url).to_return(body: 'image')

      image = described_class.download(match)
      expect(image).to have_attributes(original_filename: "AC-DC - Back in Black.jpg", read: 'image')
    end
  end
end
