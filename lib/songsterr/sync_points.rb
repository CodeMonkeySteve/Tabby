# frozen_string_literal: true

module Songsterr
  # Converts Songsterr video points (seconds at the start of each played bar) into AlphaTab flat sync points
  module SyncPoints
    extend self

    def build(points, played_bars)
      points = points.first(played_bars.size) if points.size == played_bars.size + 1
      if points.size != played_bars.size
        raise Error, "Sync point count (#{points.size}) doesn't match the number of played bars (#{played_bars.size})"
      end

      played_bars.zip(points).map do |(bar_index, occurrence), seconds|
        { barIndex: bar_index, barOccurence: occurrence, barPosition: 0, millisecondOffset: (seconds * 1000).round }
      end
    end
  end
end
