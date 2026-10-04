class AddSlugToPlaylists < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :playlists, :slug, :string
    add_index :playlists, %i[user_id slug], unique: true, algorithm: :concurrently

    # generates the current playlists' slugs (and their friendly_id history)
    Playlist.reset_column_information
    Playlist.find_each(&:save!)
  end

  def down
    execute "DELETE FROM friendly_id_slugs WHERE sluggable_type = 'Playlist'"
    remove_index :playlists, %i[user_id slug], algorithm: :concurrently
    remove_column :playlists, :slug
  end
end
