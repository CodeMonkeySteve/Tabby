# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dashboard do
  let(:today) { Date.new(2026, 9, 30) } # a Wednesday
  let(:user) { create(:user, instrument_types: %w[bass]) }
  let(:dashboard) { described_class.new(user, today:) }
  let(:bass_song) { create(:song, title: "Bass Song", track_types: %w[guitar bass]) }
  let(:keys_song) { create(:song, title: "Keys Song", track_types: %w[keys]) }

  def play(song, days_ago, minutes)
    create(:play_history, user:, song:, date: today - days_ago, duration: minutes * 60.0)
  end

  it "shows playlists by name, with their songs in playlist order" do
    create(:playlist, user:, name: "Warmups", songs: [keys_song, bass_song])
    create(:playlist, user:, name: "Gig")
    create(:playlist, name: "Someone else's", user: create(:user))

    expect(dashboard.playlists.map(&:name)).to eq ["Gig", "Warmups"]
    expect(dashboard.playlist_songs(dashboard.playlists.second)).to eq [keys_song, bass_song]
  end

  it "shows recently played songs with their last play date and total practice time" do
    play(bass_song, 5, 10)
    play(bass_song, 3, 5)
    play(keys_song, 1, 2)
    create(:play_history, user: create(:user), song: bass_song, date: today)

    expect(dashboard.recent_plays.map(&:to_h)).to eq [
      { song: keys_song, date: today - 1, seconds: 120.0 },
      { song: bass_song, date: today - 3, seconds: 900.0 },
    ]
  end

  it "shows recently added songs for the user's instruments, or all songs without any" do
    bass_song.update!(created_at: 2.days.ago)
    keys_song
    newer_bass_song = create(:song, title: "Newer", track_types: %w[bass])

    expect(dashboard.recent_songs).to eq [newer_bass_song, bass_song]
    user.instrument_types = []
    expect(described_class.new(user, today:).recent_songs.first(2)).to eq [newer_bass_song, keys_song]
  end

  it "shows daily practice for whole weeks through today" do
    play(bass_song, 0, 5)
    play(keys_song, 0, 10)
    play(bass_song, 1, 30)
    play(bass_song, 2, 90)
    play(bass_song, 200, 10)

    expect(dashboard.activity_start).to eq Date.new(2026, 7, 6) # a Monday
    expect(dashboard.activity.first.date).to eq dashboard.activity_start
    expect(dashboard.activity.last).to eq Dashboard::Day.new(today, 900.0)
    expect(dashboard.activity_weeks).to have(Dashboard::ACTIVITY_WEEKS).items
    expect(dashboard.activity_weeks.last.map(&:date)).to eq (Date.new(2026, 9, 28)..today).to_a
    expect(dashboard.activity.last(4).map(&:level)).to eq [0, 4, 3, 2]
  end

  it "summarizes the current week, starting Monday" do
    play(bass_song, 3, 20) # last Sunday
    play(bass_song, 0, 5)
    play(keys_song, 2, 10)
    play(keys_song, 1, 0)

    expect(dashboard.week_summary).to eq Dashboard::Summary.new(
      date: Date.new(2026, 9, 28), seconds: 900.0, songs: 2, new_songs: 1, top_song: keys_song,
    )
  end

  describe "#session_summary" do
    it "summarizes today's practice" do
      play(bass_song, 0, 5)
      play(keys_song, 0, 10)
      play(bass_song, 4, 20)

      expect(dashboard.session_summary).to eq Dashboard::Summary.new(
        date: today, seconds: 900.0, songs: 2, new_songs: 1, top_song: keys_song,
      )
    end

    it "summarizes the last session before practicing today, or nothing without any" do
      play(bass_song, 0, 0)
      play(bass_song, 4, 20)
      play(keys_song, 10, 5)

      expect(dashboard.session_summary).to eq Dashboard::Summary.new(
        date: today - 4, seconds: 1200.0, songs: 1, new_songs: 1, top_song: bass_song,
      )
      expect(described_class.new(create(:user), today:).session_summary).to eq Dashboard::Summary.new(
        date: today, seconds: 0, songs: 0, new_songs: 0, top_song: nil,
      )
    end
  end

  describe "#weeks_in_a_row" do
    it "counts consecutive weeks of practice through the current week" do
      [0, 3, 9, 10, 30].each { play(bass_song, it, 5) } # this week, the last two weeks, and a month ago
      expect(dashboard.weeks_in_a_row).to eq 3
    end

    it "counts through last week before practicing this week, ignoring days without practice time" do
      play(bass_song, 0, 0)
      [3, 10].each { play(bass_song, it, 5) }
      expect(dashboard.weeks_in_a_row).to eq 2
      expect(described_class.new(create(:user), today:).weeks_in_a_row).to eq 0
    end
  end
end
