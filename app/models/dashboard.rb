# frozen_string_literal: true

# A user's practice overview: their playlists, recently played and added songs, and daily practice activity
class Dashboard
  RECENT_LIMIT = 8

  # About 90 days, in whole weeks (Sunday first), like GitHub's contribution graph
  ACTIVITY_WEEKS = 13

  # Minutes of practice for activity levels 2, 3, and 4 (level 1 is any practice, level 0 none)
  ACTIVITY_LEVEL_MINUTES = [10, 30, 60].freeze

  Day = Data.define(:date, :seconds) do
    def level
      return 0 unless seconds.positive?

      1 + ACTIVITY_LEVEL_MINUTES.count { seconds >= it.minutes }
    end
  end

  RecentPlay = Data.define(:song, :date, :seconds)

  attr_reader :user, :today

  def initialize(user, today: Date.current)
    @user = user
    @today = today
  end

  def playlists
    @playlists ||= user.playlists.order(:name).to_a
  end

  # A playlist's songs in playlist order, with all playlists' songs loaded in one query
  def playlist_songs(playlist)
    @playlist_songs ||= Song.where(id: playlists.flat_map(&:song_ids)).index_by(&:id)
    @playlist_songs.values_at(*playlist.song_ids).compact
  end

  # The user's most recently played songs, with the last date each was played and its total practice time
  def recent_plays
    @recent_plays ||= begin
      rows = user.play_histories.group(:song_id)
        .order(Arel.sql('MAX(date) DESC, SUM(duration) DESC'))
        .limit(RECENT_LIMIT)
        .pluck(:song_id, Arel.sql('MAX(date)'), Arel.sql('SUM(duration)'))
      songs = Song.where(id: rows.map(&:first)).index_by(&:id)
      rows.filter_map { |song_id, date, seconds| RecentPlay.new(songs[song_id], date, seconds) if songs[song_id] }
    end
  end

  # The most recently added songs with a track for the user's instruments (or any songs, if they haven't chosen any)
  def recent_songs
    @recent_songs ||= Song.for_instruments(user.instrument_types).order(created_at: :desc).limit(RECENT_LIMIT).to_a
  end

  # Each day's practice, from the first day of the activity graph through today
  def activity
    @activity ||= begin
      seconds = user.play_histories.where(date: activity_start..today).group(:date).sum(:duration)
      (activity_start..today).map { Day.new(it, seconds.fetch(it, 0)) }
    end
  end

  # The activity graph's columns, one per week
  def activity_weeks
    activity.each_slice(7).to_a
  end

  def activity_start
    today.beginning_of_week(:sunday) - (ACTIVITY_WEEKS - 1).weeks
  end

  def activity_seconds
    activity.sum(&:seconds)
  end

  def activity_days
    activity.count { it.seconds.positive? }
  end

  # Consecutive days of practice through today, or through yesterday if the user hasn't practiced yet today
  def streak
    dates = user.play_histories.where.not(duration: ..0).distinct.order(date: :desc).pluck(:date)
    day = dates.first == today ? today : today.yesterday
    dates.drop_while { it > day }.each_with_index.take_while { |date, index| date == day - index }.size
  end
end
