class CreateTables < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name
      t.string :email, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :credentials do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :uid, null: false
      t.jsonb :token
      t.timestamps
    end
    add_index :credentials, %i[provider uid], unique: true

    create_table :songs do |t|
      t.string :title, null: false
      t.string :artist
      t.string :slug
      t.integer :tempo
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

    create_table :playlists do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.bigint :song_ids, array: true, null: false, default: []
      t.timestamps
    end
    add_index :playlists, %i[user_id name]

    create_table :play_histories do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :song, null: false, foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.float :duration, null: false, default: 0
    end
    add_index :play_histories, %i[user_id song_id date], unique: true
  end
end
