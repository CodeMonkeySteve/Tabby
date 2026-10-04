# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Songsterr::Client do
  let(:page) { Songsterr::Page.new(file_fixture('songsterr/page.html').read) }
  let(:client) { described_class.new(page) }
  let(:track_url) { 'https://dqsljvtekg760.cloudfront.net/2687597/3537915/v4-6-3-EAi4zBWPBvY-23HR/%d.json' }
  let(:video_points_url) { 'https://www.songsterr.com/api/video-points/2687597/3537915/list' }

  def stub_track(part_id, body = file_fixture("songsterr/#{part_id}.json.gz").binread)
    stub_request(:get, format(track_url, part_id)).to_return(body:)
  end

  describe '#track' do
    it "downloads and decompresses track JSON" do
      stub_track(1)
      track = client.track(1)
      expect(track).to include('instrument' => "Electric Bass (finger)", 'tuning' => [43, 38, 33, 28])
      expect(track['measures']).to have(150).items
    end

    it "accepts track JSON that is already decompressed" do
      stub_track(1, Zlib.gunzip(file_fixture('songsterr/1.json.gz').binread))
      expect(client.track(1)['measures']).to have(150).items
    end

    it "raises on HTTP errors" do
      stub_request(:get, format(track_url, 1)).to_return(status: 403)
      expect { client.track(1) }.to raise_error(Songsterr::Error, /403/)
    end
  end

  it "downloads all tracks in page order" do
    (0..2).each { stub_track(it) }
    expect(client.tracks.pluck('partId')).to eq [0, 1, 2]
  end

  describe '#video_points' do
    let(:video_points) { JSON.parse(file_fixture('songsterr/video_points.json').read) }
    let(:original) { page.videos.first }

    before { stub_request(:get, video_points_url).to_return(body: ->(_request) { JSON.generate(video_points) }) }

    it "returns the points for the given video" do
      points = client.video_points(original)
      expect(points).to have(150).items
      expect(points.first(2)).to eq [0, 2.12]
    end

    it "distinguishes videos of the same YouTube video by their Songsterr ID" do
      video_points.unshift(video_points.first.merge('id' => 1, 'feature' => 'alternative', 'points' => [0, 4.24]))
      expect(client.video_points(original)).to have(150).items
      expect(client.video_points(original.merge('id' => 1))).to eq [0, 4.24]
    end

    it "downloads the list of videos' points once" do
      client.video_points(original)
      client.video_points(page.videos.second)
      expect(a_request(:get, video_points_url)).to have_been_made.once
    end

    it "raises when the video has no points" do
      expect { client.video_points('id' => 1, 'videoId' => 'unknown') }.to raise_error(Songsterr::Error, /unknown/)
    end
  end
end
