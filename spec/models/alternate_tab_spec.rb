# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlternateTab do
  let(:song) { create(:song, track_types: %w[bass]) }
  let(:five_string) { [43, 38, 33, 28, 23] }

  def error_attributes(tab) = tab.tap(&:valid?).errors.attribute_names

  it "validates the track, tuning, and strings" do
    expect(build(:alternate_tab, tuning: five_string, strings: { '0' => 5, '476' => 1 }, optimizer: 'beam')).to be_valid
    expect(build(:alternate_tab, tuning: [60], strings: { '3' => 1 })).to be_valid
    expect(error_attributes(build(:alternate_tab, track_index: -1, tuning: [], note_count: -1)))
      .to eq %i[track_index tuning note_count]
    expect(error_attributes(build(:alternate_tab, tuning: [128, 40]))).to eq %i[tuning]
    expect(error_attributes(build(:alternate_tab, strings: { '477' => 1 }))).to eq %i[strings] # past the last note
    expect(error_attributes(build(:alternate_tab, strings: { '0' => 5 }))).to eq %i[strings] # past the last string
    expect(error_attributes(build(:alternate_tab, strings: { '0' => 0 }))).to eq %i[strings]
    expect(error_attributes(build(:alternate_tab, strings: { 'a' => 1 }))).to eq %i[strings]
    expect(error_attributes(build(:alternate_tab, strings: { '0' => '1' }))).to eq %i[strings]
    expect(error_attributes(build(:alternate_tab, strings: [1]))).to eq %i[strings]
  end

  it "is unique per user, song, track, and tuning" do
    tab = create(:alternate_tab, song:)
    other_track = create(:alternate_tab, user: tab.user, song:, track_index: 1)
    other_tuning = create(:alternate_tab, user: tab.user, song:, tuning: five_string)
    expect { create(:alternate_tab, user: tab.user, song:) }.to raise_error ActiveRecord::RecordNotUnique
    expect(AlternateTab.in_tuning([43, 38, 33, 28])).to contain_exactly tab, other_track
    expect(AlternateTab.in_tuning(five_string)).to contain_exactly other_tuning
    expect(tab.user.alternate_tabs).to contain_exactly tab, other_track, other_tuning
    expect(song.alternate_tabs).to contain_exactly tab, other_track, other_tuning
  end

  it "merges string changes" do
    tab = create(:alternate_tab, song:, strings: { '1' => 2, '5' => 3 })
    expect(tab.merge_strings('5' => nil, '7' => 4)).to be true
    expect(tab.strings).to eq('1' => 2, '7' => 4)
    expect(tab.merge_strings('8' => 5)).to be false
    expect(tab.errors.attribute_names).to eq %i[strings]
    expect(tab.merge_strings('900' => 1)).to be false
    expect(tab.reload.strings).to eq('1' => 2, '7' => 4)
  end

  it "has the player's attributes" do
    tab = create(:alternate_tab, song:, strings: { '3' => 2 }, optimizer: 'beam')
    expect(tab.for_player).to eq(id: tab.id, trackIndex: 0, tuning: [43, 38, 33, 28], noteCount: 477, strings: { '3' => 2 },
                                 optimizer: 'beam')
  end

  it "is deleted when the song's score changes" do
    tab = create(:alternate_tab, song:)
    song.update!(title: "New Title")
    expect(AlternateTab.exists?(tab.id)).to be true

    song.update!(score: upload_fixture('Tears for Fears - Head Over Heels.gpx', 'audio/x-gtp'))
    expect(AlternateTab.exists?(tab.id)).to be false
  end
end
