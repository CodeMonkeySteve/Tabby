class CreateAlternateTabs < ActiveRecord::Migration[8.1]
  def change
    # the foreign keys only briefly block writes to users and songs, since the table is new (and so empty)
    safety_assured do
      # a user's own fingering of a score track, in a tuning
      create_table :alternate_tabs, id: :uuid, default: -> { 'uuidv7()' } do |t|
        t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.references :song, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
        t.integer :track_index, null: false # score track index
        t.integer :tuning, array: true, null: false # MIDI note of each open string, highest string first (as in AlphaTab)
        t.integer :note_count, null: false # notes in the track (see app/javascript/lib/track_tab.js)
        t.jsonb :strings, null: false, default: {} # string (1 is the lowest) by note index, where it differs from the score's
        t.string :optimizer # the fingering optimizer that generated the strings, if any

        t.timestamps
        t.index %i[user_id song_id track_index tuning], unique: true
      end
    end
  end
end
