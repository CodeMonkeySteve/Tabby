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

  describe "with a different number of points and played bars" do
    let(:played_bars) { (0...20).map { [it, 0] } }

    it "syncs as many bars as there are points, with a warning" do
      warnings = []
      sync_points = described_class.build((0...15).to_a, played_bars) { warnings << it }
      expect(sync_points.pluck(:barIndex)).to eq (0...15).to_a
      expect(warnings).to eq ["Video has 15 sync points for 20 played bars; bars after 15 will follow the score's tempo"]
    end

    it "ignores extra points, with a warning" do
      warnings = []
      sync_points = described_class.build((0...22).to_a, played_bars) { warnings << it }
      expect(sync_points.pluck(:millisecondOffset)).to eq((0...20).map { it * 1000 })
      expect(warnings).to eq ["Video has 22 sync points for 20 played bars; ignoring the last 2"]
    end
  end

  it "raises, with the time of the last point, when there are far too few points, or far too many" do
    expect { described_class.build([0, 61.5], played_bars) }
      .to raise_error(Songsterr::Error, "Video has 2 sync points for 4 played bars, ending at 1:01")
    expect { described_class.build((0...6).to_a, played_bars) }.to raise_error(Songsterr::Error, /\(6\).*\(4\)/)
  end
end
