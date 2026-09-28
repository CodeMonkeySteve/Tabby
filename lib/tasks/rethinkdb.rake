# frozen_string_literal: true

# One-time migration of the NoBrainer/RethinkDB data to ActiveRecord/PostgreSQL.  Records get new integer ids, so references
# are remapped as each table is copied.  Uploaded files are untouched, since the Shrine attachment data (and so the storage paths)
# are copied as-is.  Documents that duplicate a unique key (which NoBrainer's racy uniqueness validations allowed) are merged into
# the first copy.
module RethinkImport
  extend self

  TIMESTAMPS = %w[created_at updated_at].freeze

  def run
    require 'rethinkdb'

    @ids = Hash.new { |hash, table| hash[table] = {} }
    ActiveRecord::Base.transaction do
      [User, Credential, Song, Playlist].each do |model|
        model.none? or abort "The #{model.table_name} table isn't empty, run `bin/rails db:reset` first"
      end

      import(User, 'users', unique_by: %i[email]) { it.slice('name', 'email', *TIMESTAMPS) }

      # keep the latest token
      merge_credential = ->(cred, attrs) { cred.update_columns(attrs.slice(:token, :updated_at)) }
      import(Credential, 'credentials', unique_by: %i[provider uid], merge: merge_credential) do |doc|
        user_id = ref(:users, doc['user_id'], doc) or next
        doc.slice('provider', 'uid', 'token', *TIMESTAMPS).merge(user_id:)
      end

      # keep the most recently updated copy's values, filling in any it lacks from the other copies
      merge_song = ->(song, attrs) do
        attrs = attrs.except(:created_at).compact
        attrs = attrs.reject { |name, _| song[name].present? } if attrs[:updated_at] <= song.updated_at
        song.update_columns(attrs)
      end
      import(Song, 'songs', unique_by: %i[title artist], merge: merge_song) do |doc|
        doc.slice(*%w[title artist slug tempo score_data audio_data cover_data sync_points jellyfin_id songsterr_id],
                  *TIMESTAMPS)
      end

      import(Playlist, 'playlists') do |doc|
        user_id = ref(:users, doc['user_id'], doc) or next
        song_ids = doc['song_ids'].to_a.filter_map { ref(:songs, it, doc) }.uniq
        doc.slice('name', *TIMESTAMPS).merge(user_id:, song_ids:)
      end

      # don't need to preserve play history
      #
      # merge_history = ->(history, attrs) { history.update_columns(duration: history.duration + attrs[:duration]) }
      # import(PlayHistory, 'play_histories', unique_by: %i[user_id song_id date], merge: merge_history) do |doc|
      #   user_id = ref(:users, doc['user_id'], doc) or next
      #   song_id = ref(:songs, doc['song_id'], doc) or next
      #   doc.slice('duration').merge(user_id:, song_id:, date: doc['date'].utc.to_date)
      # end
    end

  ensure
    @conn&.close
  end

  private

  def conn
    @conn ||= begin
      url = URI(ENV['RETHINKDB_URL'] || Rails.application.credentials.dig(:rethinkdb, :url) || 'rethinkdb://localhost')
      db = url.path.delete_prefix('/').presence || "tabby_#{Rails.env}"
      puts "Importing from RethinkDB #{url.host}/#{db}"
      RethinkDB::RQL.new.connect(host: url.host, port: url.port, db:, user: url.user, password: url.password)
    end
  end

  # Copies each document of a RethinkDB table, as mapped by the block to column values (or nil to skip it), into a model's table.
  # A document with the same `unique_by` values as an earlier one is passed to `merge` (with the earlier record) instead.
  def import(model, table, unique_by: nil, merge: nil)
    docs = RethinkDB::RQL.new.table(table).order_by('created_at', 'id').run(conn)
    copied = merged = 0
    docs.each do |doc|
      attrs = yield(doc)&.symbolize_keys or next
      @ids[table.to_sym][doc['id']] =
        if unique_by && (existing = model.find_by(attrs.slice(*unique_by)))
          merge&.call(existing, attrs)
          merged += 1
          existing.id
        else
          copied += 1
          model.insert!(attrs, returning: :id, record_timestamps: false).rows.first.first
        end
    end
    puts "  #{table}: #{copied} of #{docs.size} copied, #{merged} merged into duplicates"
  end

  # Returns the new id for a document's reference to another table's old id, or nil (with a warning) if it doesn't exist
  def ref(table, old_id, doc)
    @ids[table].fetch(old_id) do
      warn "  #{doc['id']} references missing #{table.to_s.singularize} #{old_id}"
      nil
    end
  end
end

namespace :rethinkdb do
  desc "Copy all data from RethinkDB (RETHINKDB_URL or the rethinkdb.url credential) into the empty PostgreSQL database"
  task import: :environment do
    RethinkImport.run
    Rake::Task['songs:classify_tracks'].invoke # songs are inserted without callbacks
  end
end
