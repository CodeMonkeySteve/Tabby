# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Songsterr::Search do
  let(:api_url) { 'https://www.songsterr.com/api/songs' }

  it "returns the non-junk matches for a query" do
    stub_request(:get, api_url).with(query: { pattern: 'head over heels', size: '20' })
      .to_return(body: file_fixture('songsterr/search.json').read)
    results = described_class.call("head over heels")

    expect(results.map(&:song_id)).to eq [20361, 1041]
    expect(results.first).to have_attributes(artist: "Tears for Fears", title: "Head Over Heels")
    expect(results.first.tracks.pluck('hash')).to include 'other_xMtjYRgy'
  end

  it "decodes the HTML entities in some older songs' names" do
    song = { songId: 16307, artist: "Raszer", title: "Przekszta&#322;&#263; To W Ma&#322;Pe &amp; Co", tracks: [] }
    stub_request(:get, api_url).with(query: hash_including({})).to_return(body: JSON.generate([song]))
    expect(described_class.call("x").first.title).to eq "Przekształć To W MałPe & Co"
  end

  it "raises on invalid responses" do
    stub_request(:get, api_url).with(query: hash_including({})).to_return(body: '<html>oops</html>')
    expect { described_class.call("x") }.to raise_error(Songsterr::Error, /Invalid JSON/)

    stub_request(:get, api_url).with(query: hash_including({})).to_return(status: 503)
    expect { described_class.call("x") }.to raise_error(Songsterr::Error, /Failed to fetch/)
  end
end
