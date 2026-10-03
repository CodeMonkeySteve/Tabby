# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Song::SongsterrMatch do
  let(:tracks) { JSON.parse(file_fixture('songsterr/search.json').read).first['tracks'] }
  let(:result) { Songsterr::Result.new(song_id: 20361, artist: "Tears for Fears", title: "Head Over Heels", tracks:) }

  it "classifies tracks by Songsterr's part, or like a score track for other parts" do
    match = described_class.from_result(result)
    # the "other" piano track is keys
    expect(match).to have_attributes(song_id: 20361, artist: "Tears for Fears", title: "Head Over Heels",
                                     track_types: %w[vocals guitar bass keys drums],
                                     instrument_types: %w[drums bass guitar keys vocals])
  end

  it "builds Songsterr page URLs from the id and a slug" do
    match = described_class.from_result(result)
    expect(match.url).to eq 'https://www.songsterr.com/a/wsa/tears-for-fears-head-over-heels-tab-s20361'
    expect(match.frame_id).to eq 'songsterr_20361'

    odd = described_class.new(song_id: 7, artist: "AC/DC", title: "Motörhead / ../../evil?x=1#y", track_types: [])
    expect(URI(odd.url)).to have_attributes(scheme: 'https', host: 'www.songsterr.com', query: nil, fragment: nil)
    expect(odd.url).to end_with '-tab-s7'
  end

  it "links to the first track of an instrument type, or the default track without one" do
    match = described_class.new(song_id: 7, artist: "A", title: "B", track_types: %w[vocals guitar guitar bass])
    expect(match.url('guitar')).to eq 'https://www.songsterr.com/a/wsa/a-b-tab-s7t1'
    expect(match.url(:vocals)).to end_with '-tab-s7t0'
    expect(match.url('drums')).to end_with '-tab-s7'
    expect(match.url(nil)).to end_with '-tab-s7'
  end

  it "round-trips through a Hash, for job arguments" do
    match = described_class.from_result(result)
    expect(described_class.new(**match.to_h)).to eq match
  end
end
