# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_27_071000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  # These are the common tables
  create_table "credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.jsonb "token"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider", "uid"], name: "index_credentials_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_credentials_on_user_id"
  end

  create_table "play_histories", force: :cascade do |t|
    t.date "date", null: false
    t.float "duration", default: 0.0, null: false
    t.bigint "song_id", null: false
    t.bigint "user_id", null: false
    t.index ["song_id"], name: "index_play_histories_on_song_id"
    t.index ["user_id", "song_id", "date"], name: "index_play_histories_on_user_id_and_song_id_and_date", unique: true
  end

  create_table "playlists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "song_ids", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "name"], name: "index_playlists_on_user_id_and_name"
  end

  create_table "songs", force: :cascade do |t|
    t.string "artist"
    t.jsonb "audio_data"
    t.jsonb "cover_data"
    t.datetime "created_at", null: false
    t.string "instruments", array: true
    t.string "jellyfin_id"
    t.jsonb "score_data", null: false
    t.string "slug"
    t.integer "songsterr_id"
    t.jsonb "sync_points"
    t.integer "tempo"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["artist", "title"], name: "index_songs_on_artist_and_title"
    t.index ["jellyfin_id"], name: "index_songs_on_jellyfin_id"
    t.index ["slug"], name: "index_songs_on_slug", unique: true
    t.index ["songsterr_id"], name: "index_songs_on_songsterr_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "credentials", "users", on_delete: :cascade
  add_foreign_key "play_histories", "songs", on_delete: :cascade
  add_foreign_key "play_histories", "users", on_delete: :cascade
  add_foreign_key "playlists", "users", on_delete: :cascade
end
