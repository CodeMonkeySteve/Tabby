class AddPlayerSettingsToSongNotes < ActiveRecord::Migration[8.1]
  def change
    # player settings (null for the player's defaults)
    add_column :song_notes, :volume, :integer # master volume percentage
    add_column :song_notes, :tracks, :integer, array: true # indexes of the shown score tracks
    add_column :song_notes, :muted_tracks, :integer, array: true # indexes of the muted score tracks
    add_column :song_notes, :solo_tracks, :integer, array: true # indexes of the score tracks played solo
    add_column :song_notes, :track_volumes, :jsonb # score track volumes (0-16) by track index
  end
end
