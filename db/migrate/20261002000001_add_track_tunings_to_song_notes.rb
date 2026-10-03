class AddTrackTuningsToSongNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :song_notes, :track_tunings, :jsonb # chosen tunings (see AlternateTab#tuning) by score track index
  end
end
