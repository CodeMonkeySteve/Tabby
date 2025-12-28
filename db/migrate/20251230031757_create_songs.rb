class CreateSongs < ActiveRecord::Migration[8.1]
  def change
    create_table :songs do |t|
      t.string :title, null: false
      t.string :artist
      # t.column :sync_points, :integer, array: true, default: []
      t.timestamps
    end
  end
end
