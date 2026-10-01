class CreateSongsterrSongs < ActiveRecord::Migration[8.1]
  def change
    add_column :songs, :genres, :string, array: true, null: false, default: []

    # the foreign key only briefly blocks writes to songs, since the table is new (and so empty)
    safety_assured do
      # the source of a song imported from Songsterr, with its Songsterr song ID as the primary key
      create_table :songsterr_songs, id: :integer, default: nil do |t|
        t.references :song, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
        t.integer :revision_id # the imported revision; null for songs imported before it was recorded
        t.jsonb :data, null: false, default: {} # Songsterr's metadata, other than score details (see SongsterrSong)
        t.timestamps
      end

      # copy songs.songsterr_id, which Song now ignores (and a later migration will drop); there are few enough imported songs to
      # copy in one statement
      reversible do |dir|
        dir.up do
          execute <<~SQL.squish
            INSERT INTO songsterr_songs (id, song_id, created_at, updated_at)
            SELECT DISTINCT ON (songsterr_id) songsterr_id, id, updated_at, updated_at
            FROM songs
            WHERE songsterr_id IS NOT NULL
            ORDER BY songsterr_id, updated_at DESC
          SQL
        end
      end
    end
  end
end
