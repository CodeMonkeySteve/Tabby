# frozen_string_literal: true

# A user's practice overview: their playlists, recently played and added songs, daily practice activity, and summaries of
# this week's and the latest session's practice
class Dashboard
  RECENT_LIMIT = 8

  # About 90 days, in whole weeks (Monday first, so that a weekend falls within one week), like GitHub's contribution graph
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

  # Practice from a date through today: total seconds, distinct songs, songs played for the first time, and the most practiced song
  Summary = Data.define(:date, :seconds, :songs, :new_songs, :top_song)

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
    week_start - (ACTIVITY_WEEKS - 1).weeks
  end

  def week_summary
    @week_summary ||= summary(week_start..today)
  end

  # Today's practice, or the latest session's if the user hasn't practiced yet today
  def session_summary
    @session_summary ||= begin
      date = practice.where(date: ..today).maximum(:date) || today
      summary(date..date)
    end
  end

  # Consecutive weeks of practice through this week, or through last week if the user hasn't practiced yet this week
  def weeks_in_a_row
    weeks = practice.where(date: ..today).distinct.order(date: :desc).pluck(:date).map { it.beginning_of_week(:monday) }.uniq
    week = weeks.first == week_start ? week_start : week_start - 1.week
    weeks.drop_while { it > week }.each_with_index.take_while { |start, index| start == week - index.weeks }.size
  end

private

  def week_start
    today.beginning_of_week(:monday)
  end

  # Play histories with practice time
  def practice
    user.play_histories.where.not(duration: ..0)
  end

  def summary(dates)
    seconds = practice.where(date: dates).group(:song_id).sum(:duration)
    first_plays = practice.where(song_id: seconds.keys).group(:song_id).minimum(:date)
    top_song_id = seconds.max_by(&:last)&.first
    Summary.new(
      date: dates.begin, seconds: seconds.values.sum, songs: seconds.size, new_songs: first_plays.values.count { it >= dates.begin },
      top_song: top_song_id && Song.find_by(id: top_song_id),
    )
  end
end
