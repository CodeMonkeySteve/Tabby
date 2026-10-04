# frozen_string_literal: true

module Songsterr
  # Converts Songsterr video points (seconds at the start of each played bar) into AlphaTab flat sync points
  module SyncPoints
    extend self

    # A video synced before its tab was edited (e.g. a repeat was added) can be off by a few bars; beyond this it's probably the
    # wrong video
    MAX_OVERAGE = 0.1
    # A video of a shorter edit of the song than the tab (e.g. a single edit of an album track) syncs only the bars it plays, so it
    # just needs to cover most of the tab
    MIN_COVERAGE = 0.75

    # Yields a warning message when the point and played bar counts differ
    def build(points, played_bars)
      points = points.first(played_bars.size) if points.size == played_bars.size + 1
      if points.size < played_bars.size * MIN_COVERAGE
        # The points end early when Songsterr's sync of a video was abandoned partway through the song, or are sparser when the video
        # was synced to an earlier revision of the tab with a different bar layout
        last = points.last.to_i
        raise Error, "Video has #{points.size} sync points for #{played_bars.size} played bars, " \
                     "ending at #{last / 60}:#{format('%02d', last % 60)}"
      elsif points.size > played_bars.size * (1 + MAX_OVERAGE)
        raise Error, "Sync point count (#{points.size}) doesn't match the number of played bars (#{played_bars.size})"
      end

      if points.size < played_bars.size
        last_bar_number = played_bars[points.size - 1].first + 1
        yield "Video has #{points.size} sync points for #{played_bars.size} played bars; " \
              "bars after #{last_bar_number} will follow the score's tempo" if block_given?
      elsif points.size > played_bars.size
        yield "Video has #{points.size} sync points for #{played_bars.size} played bars; " \
              "ignoring the last #{points.size - played_bars.size}" if block_given?
      end

      played_bars.zip(points).take(points.size).map do |(bar_index, occurrence), seconds|
        { barIndex: bar_index, barOccurence: occurrence, barPosition: 0, millisecondOffset: (seconds * 1000).round }
      end
    end
  end
end
