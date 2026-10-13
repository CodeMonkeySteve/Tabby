class CreateFriendlyIdSlugs < ActiveRecord::Migration[8.1]
  def change
    # friendly_id's history of each record's slugs, so old URLs still find it
    create_table :friendly_id_slugs, id: :uuid, default: ->{ 'uuidv7()' } do |t|
      t.string :slug, null: false
      t.references :sluggable, type: :uuid, polymorphic: true, null: false
      t.string :scope
      t.datetime :created_at

      t.index %i[slug sluggable_type scope], unique: true, nulls_not_distinct: true
    end

    # records the current slugs, since friendly_id only records slugs as they're saved
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<~SQL
            INSERT INTO friendly_id_slugs (slug, sluggable_id, sluggable_type, created_at)
            SELECT slug, id, 'Song', created_at FROM songs WHERE slug IS NOT NULL
          SQL
        end
      end
    end
  end
end
