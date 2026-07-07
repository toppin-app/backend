class CreateBlackCoffeeConcertImports < ActiveRecord::Migration[6.0]
  def up
    create_concert_import_runs
    create_concert_import_items
  end

  def down
    drop_table :black_coffee_concert_import_items if table_exists?(:black_coffee_concert_import_items)
    drop_table :black_coffee_concert_import_runs if table_exists?(:black_coffee_concert_import_runs)
  end

  private

  def create_concert_import_runs
    return if table_exists?(:black_coffee_concert_import_runs)

    create_table :black_coffee_concert_import_runs do |t|
      t.string :source, null: false, default: 'songkick'
      t.string :status, null: false, default: 'pending'
      t.string :mode, null: false, default: 'dry_run'
      t.text :source_url
      t.text :source_paths
      t.integer :max_pages_per_source, null: false, default: 1
      t.integer :max_events, null: false, default: 500
      t.decimal :request_delay_seconds, precision: 6, scale: 2, null: false, default: 10.0
      t.string :strict_country_code, null: false, default: 'ES'
      t.boolean :include_festivals, null: false, default: false
      t.boolean :download_images, null: false, default: true
      t.boolean :only_future, null: false, default: true
      t.boolean :auto_publish, null: false, default: false
      t.boolean :preserve_manual_edits, null: false, default: true
      t.bigint :created_by_id
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :robots_requests_count, null: false, default: 0
      t.integer :listing_requests_count, null: false, default: 0
      t.integer :detail_requests_count, null: false, default: 0
      t.integer :candidates_found_count, null: false, default: 0
      t.integer :outside_country_skipped_count, null: false, default: 0
      t.integer :festival_skipped_count, null: false, default: 0
      t.integer :duplicate_skipped_count, null: false, default: 0
      t.integer :invalid_skipped_count, null: false, default: 0
      t.integer :past_skipped_count, null: false, default: 0
      t.integer :images_downloaded_count, null: false, default: 0
      t.integer :items_created_count, null: false, default: 0
      t.integer :venues_created_count, null: false, default: 0
      t.integer :needs_review_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.json :summary_payload
      t.text :error_message
      t.timestamps
    end

    add_index :black_coffee_concert_import_runs, :status, name: 'idx_bc_concert_runs_status'
    add_index :black_coffee_concert_import_runs, :source, name: 'idx_bc_concert_runs_source'
    add_index :black_coffee_concert_import_runs, :created_at, name: 'idx_bc_concert_runs_created_at'
    add_index :black_coffee_concert_import_runs, :created_by_id, name: 'idx_bc_concert_runs_created_by'
    add_foreign_key :black_coffee_concert_import_runs,
                    :users,
                    column: :created_by_id,
                    name: 'fk_bc_concert_runs_created_by',
                    on_delete: :nullify
  end

  def create_concert_import_items
    return if table_exists?(:black_coffee_concert_import_items)

    create_table :black_coffee_concert_import_items do |t|
      t.references :black_coffee_concert_import_run,
                   null: false,
                   foreign_key: true,
                   index: { name: 'idx_bc_concert_items_run' }
      t.string :venue_id
      t.string :status, null: false, default: 'pending'
      t.string :source, null: false, default: 'songkick'
      t.text :source_url
      t.string :source_path
      t.string :source_event_id
      t.string :fingerprint
      t.string :name
      t.string :venue_name
      t.string :city
      t.string :state
      t.string :country
      t.string :country_code
      t.date :start_date
      t.date :end_date
      t.text :image_url
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.string :coordinates_source
      t.string :coordinates_confidence
      t.text :source_description
      t.string :source_description_language
      t.string :source_description_status
      t.text :official_url
      t.text :ticket_url
      t.text :warning_message
      t.text :error_message
      t.json :raw_payload
      t.json :normalized_payload
      t.timestamps
    end

    add_index :black_coffee_concert_import_items, :venue_id, name: 'idx_bc_concert_items_venue'
    add_index :black_coffee_concert_import_items, :status, name: 'idx_bc_concert_items_status'
    add_index :black_coffee_concert_import_items, :source_event_id, name: 'idx_bc_concert_items_source_event'
    add_index :black_coffee_concert_import_items, :fingerprint, name: 'idx_bc_concert_items_fingerprint'
    add_index :black_coffee_concert_import_items, :country_code, name: 'idx_bc_concert_items_country'
    add_foreign_key :black_coffee_concert_import_items,
                    :venues,
                    column: :venue_id,
                    name: 'fk_bc_concert_items_venue',
                    on_delete: :nullify
  end
end
