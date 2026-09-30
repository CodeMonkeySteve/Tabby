# ActionCable's production messages (solid_cable), in the primary database, so broadcasts reach every Falcon process
class CreateSolidCableMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.bigint :channel_hash, null: false
      t.index :channel_hash
      t.index :created_at
    end
  end
end
