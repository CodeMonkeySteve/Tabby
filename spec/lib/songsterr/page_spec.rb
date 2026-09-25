# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Songsterr::Page do
  let(:url) { 'https://www.songsterr.com/a/wsa/pearl-jam-wma-bass-tab-s2687597' }
  let(:html) { file_fixture('songsterr/page.html').read }

  def page_with_meta(meta)
    described_class.new(%(<html><script id="state" type="application/json">#{JSON.generate(meta: { current: meta })}</script></html>))
  end

  it "extracts song metadata" do
    page = described_class.new(html)
    expect(page).to have_attributes(
      song_id: 2687597, revision_id: 3537915, image: 'v4-6-3-EAi4zBWPBvY-23HR',
      title: "W.M.A.", artist: "Pearl Jam", original_video_id: 'K1NcoxzNgbM',
      cloudfront_host: 'dqsljvtekg760.cloudfront.net',
    )
    expect(page.tracks.pluck('partId', 'title')).to eq [[0, "Distortion Guitar"], [1, "Electric Bass (finger)"], [2, "Drums"]]
    expect(page.metadata).to include('songId' => 2687597, 'tracks' => page.tracks)
  end

  it "ignores original videos that aren't done processing" do
    page = page_with_meta(videos: [{ videoId: 'pending', status: 'processing', feature: nil },
                                   { videoId: 'backing', status: 'done', feature: 'backing' }])
    expect(page.original_video_id).to be_nil
  end

  it "falls back to the default CloudFront host" do
    expect(page_with_meta(songId: 1).cloudfront_host).to eq Songsterr::Page::DEFAULT_CLOUDFRONT_HOST
  end

  it "raises when the page has no song data" do
    expect { described_class.new('<html></html>') }.to raise_error(Songsterr::Error, /No song data/)
    expect { described_class.new('<script id="state" type="application/json">{}</script>') }
      .to raise_error(Songsterr::Error, /No song data/)
  end

  describe '.fetch' do
    it "downloads and parses the page" do
      stub_request(:get, url).to_return(body: html)
      expect(described_class.fetch(url)).to have_attributes(title: "W.M.A.", url:)
    end

    it "raises on HTTP errors" do
      stub_request(:get, url).to_return(status: 404)
      expect { described_class.fetch(url) }.to raise_error(Songsterr::Error, /404/)
    end
  end
end
