# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SongsterrImportJob do
  include Turbo::Streams::StreamName # for stream_name_from

  before { ActionCable.server.pubsub.clear }

  # The <turbo-stream> elements broadcast to a stream by the block (turbo-rails' own capture helper needs Minitest)
  def capture_turbo_stream_broadcasts(streamables)
    name = stream_name_from(streamables)
    yield
    ActionCable.server.pubsub.broadcasts(name).map { Nokogiri::HTML5.fragment(JSON.parse(it)).at_css('turbo-stream') }
  end

  let(:user) { create(:user) }
  let(:match) { Song::SongsterrMatch.new(song_id: 20361, artist: "Tears for Fears", title: "Head Over Heels", instrument_types: %w[bass]) }
  let(:stream) { described_class.stream(user, match) }

  def perform = described_class.perform_now(user, match.to_h)

  it "saves the imported song, broadcasting progress and then the song's card" do
    allow(Song).to receive(:from_songsterr).with(match.url) do |_url, &log|
      log.("Downloading 3 tracks")
      build(:song, songsterr_song: build(:songsterr_song, id: 20361, song: nil))
    end

    broadcasts = capture_turbo_stream_broadcasts(stream) { perform }
    song = SongsterrSong.find(20361).song
    player_path = Rails.application.routes.url_helpers.player_path(song)

    expect(broadcasts.map { [it['action'], it['target']] }).to eq [%w[append songsterr_20361_log], %w[replace songsterr_20361]]
    expect(broadcasts.first.at_css('template li').text).to eq "Downloading 3 tracks"
    expect(broadcasts.last.at_css("a[href='#{player_path}']").text).to include "Play"
  end

  it "broadcasts the failure, with a retry, when the import fails" do
    allow(Song).to receive(:from_songsterr).and_raise(Songsterr::Error, "No usable recording video")

    broadcasts = capture_turbo_stream_broadcasts(stream) { perform }

    expect(broadcasts.last['action']).to eq 'replace'
    expect(broadcasts.last.at_css('.alert-danger').text).to include "No usable recording video"
    expect(broadcasts.last.at_css('form button').text).to include "Retry Import"
    expect(Song.count).to eq 0
  end

  it "broadcasts the failure of an invalid song" do
    allow(Song).to receive(:from_songsterr).and_return(Song.new(title: ""))
    broadcasts = capture_turbo_stream_broadcasts(stream) { perform }
    expect(broadcasts.last.at_css('.alert-danger').text).to include "Title can't be blank"
  end

  it "broadcasts unexpected errors before raising them, so the card doesn't spin forever" do
    allow(Song).to receive(:from_songsterr).and_raise(RuntimeError, "boom")
    broadcasts = capture_turbo_stream_broadcasts(stream) do
      expect { perform }.to raise_error RuntimeError, "boom"
    end
    expect(broadcasts.last.at_css('.alert-danger').text).to include "Import failed unexpectedly"
  end
end
