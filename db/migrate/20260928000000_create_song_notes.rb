class CreateSongNotes < ActiveRecord::Migration[8.1]
  def change
    # the foreign keys only briefly block writes to users and songs, since the table is new (and so empty)
    safety_assured do
      # a user's own data for a song
      create_table :song_notes, id: :uuid, default: ->{ 'uuidv7()' } do |t|
        t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.references :song, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

        # player settings (null for the player's defaults)
        t.float :speed
        t.boolean :looping
        t.boolean :count_in
        t.boolean :metronome
        t.integer :range_start_tick
        t.integer :range_end_tick

        t.timestamps
        t.index %i[user_id song_id], unique: true
      end
    end
  end
end
