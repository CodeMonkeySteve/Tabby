class CreateTables < ActiveRecord::Migration[8.1]
  def change
    create_enum :instrument_type, Song::INSTRUMENT_TYPES.map(&:to_s).sort

    create_table :users, id: :uuid, default: -> { 'uuidv7()' } do |t|
      t.string :name
      t.string :email, null: false
      t.enum :instrument_types, enum_type: :instrument_type, array: true, null: false, default: -> { "'{}'" }
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :credentials do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :uid, null: false
      t.jsonb :token
      t.timestamps
    end
    add_index :credentials, %i[provider uid], unique: true

    create_table :songs, id: :uuid, default: -> { 'uuidv7()' } do |t|
      t.string :title, null: false
      t.string :artist
      t.string :slug
      t.integer :tempo
      t.enum :track_types, enum_type: :instrument_type, array: true, null: false, default: -> { "'{}'" } # each score track instrument type, in order
      t.jsonb :score_data, null: false
      t.jsonb :audio_data
      t.jsonb :cover_data
      t.jsonb :sync_points
      t.string :jellyfin_id
      t.integer :songsterr_id
      t.timestamps
    end
    add_index :songs, :slug, unique: true
    add_index :songs, %i[artist title]
    add_index :songs, :jellyfin_id
    add_index :songs, :songsterr_id
    add_index :songs, :track_types, using: :gin

    create_table :playlists, id: :uuid, default: -> { 'uuidv7()' } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.uuid :song_ids, array: true, null: false, default: -> { "'{}'" }
      t.timestamps
    end
    add_index :playlists, %i[user_id name]

    create_table :play_histories do |t|
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :song, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.float :duration, null: false, default: 0
    end
    add_index :play_histories, %i[user_id song_id date], unique: true
  end
end
