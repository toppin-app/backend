class CreateBlackCoffeeConcertArtistImageCaches < ActiveRecord::Migration[6.0]
  def change
    create_table :black_coffee_concert_artist_image_caches do |t|
      t.string :identity_key, null: false
      t.string :artist_name, null: false
      t.string :canonical_name, null: false
      t.string :source_artist_id
      t.string :musicbrainz_id
      t.string :wikidata_id
      t.string :status, null: false, default: 'pending'
      t.string :provider
      t.text :image_url
      t.text :source_page_url
      t.decimal :confidence, precision: 5, scale: 2
      t.integer :image_width
      t.integer :image_height
      t.integer :image_bytes
      t.string :image_content_type
      t.string :image_sha256, limit: 64
      t.bigint :venue_image_id
      t.json :providers_checked
      t.json :evidence
      t.text :failure_reason
      t.datetime :searched_at
      t.datetime :retry_after
      t.datetime :expires_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :black_coffee_concert_artist_image_caches,
              :identity_key,
              unique: true,
              name: 'idx_bc_concert_artist_images_identity'
    add_index :black_coffee_concert_artist_image_caches,
              :source_artist_id,
              name: 'idx_bc_concert_artist_images_source_id'
    add_index :black_coffee_concert_artist_image_caches,
              :musicbrainz_id,
              name: 'idx_bc_concert_artist_images_mbid'
    add_index :black_coffee_concert_artist_image_caches,
              :wikidata_id,
              name: 'idx_bc_concert_artist_images_wikidata'
    add_index :black_coffee_concert_artist_image_caches,
              [:status, :retry_after],
              name: 'idx_bc_concert_artist_images_retry'
    add_index :black_coffee_concert_artist_image_caches,
              :venue_image_id,
              name: 'idx_bc_concert_artist_images_venue_image'
    add_foreign_key :black_coffee_concert_artist_image_caches,
                    :venue_images,
                    column: :venue_image_id,
                    on_delete: :nullify,
                    name: 'fk_bc_concert_artist_images_venue_image'

    add_column :black_coffee_concert_cover_repair_batches,
               :pending_review_count,
               :integer,
               null: false,
               default: 0 unless column_exists?(:black_coffee_concert_cover_repair_batches, :pending_review_count)
  end
end
