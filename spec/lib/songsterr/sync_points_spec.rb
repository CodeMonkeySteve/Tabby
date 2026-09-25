# frozen_string_literal: true

require 'rails_helper'
require 'songsterr'

RSpec.describe Songsterr::SyncPoints do
  let(:played_bars) { [[0, 0], [1, 0], [1, 1], [2, 0]] }

  it "pairs each played bar with its video time" do
    expect(described_class.build([0, 2.12, 4.355, 6.5], played_bars)).to eq [
      { barIndex: 0, barOccurence: 0, barPosition: 0, millisecondOffset: 0 },
      { barIndex: 1, barOccurence: 0, barPosition: 0, millisecondOffset: 2120 },
      { barIndex: 1, barOccurence: 1, barPosition: 0, millisecondOffset: 4355 },
      { barIndex: 2, barOccurence: 0, barPosition: 0, millisecondOffset: 6500 }
    ]
  end

  it "ignores a trailing end-of-song point" do
    expect(described_class.build([0, 1, 2, 3, 4], played_bars).pluck(:millisecondOffset)).to eq [0, 1000, 2000, 3000]
  end

  it "raises when the point count doesn't match the played bars" do
    expect { described_class.build([0, 1], played_bars) }.to raise_error(Songsterr::Error, /\(2\).*\(4\)/)
  end
end
