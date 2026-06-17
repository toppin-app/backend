class CreateBlackCoffeeFestivalImports < ActiveRecord::Migration[6.0]
  def up
    add_festival_source_columns_to_venues
    create_festival_import_runs
    create_festival_import_items
  end

  def down
    drop_table :black_coffee_festival_import_items if table_exists?(:black_coffee_festival_import_items)
    drop_table :black_coffee_festival_import_runs if table_exists?(:black_coffee_festival_import_runs)

    remove_index :venues, name: 'idx_venues_external_source_id' if index_exists?(:venues, [:external_source, :external_source_id], name: 'idx_venues_external_source_id')
    remove_index :venues, name: 'idx_venues_source_fingerprint' if index_exists?(:venues, :source_fingerprint, name: 'idx_venues_source_fingerprint')
    remove_index :venues, name: 'idx_venues_festival_dates' if index_exists?(:venues, [:festival_start_date, :festival_end_date], name: 'idx_venues_festival_dates')

    remove_column :venues, :external_source if column_exists?(:venues, :external_source)
    remove_column :venues, :external_source_url if column_exists?(:venues, :external_source_url)
    remove_column :venues, :external_source_id if column_exists?(:venues, :external_source_id)
    remove_column :venues, :source_fingerprint if column_exists?(:venues, :source_fingerprint)
    remove_column :venues, :festival_start_date if column_exists?(:venues, :festival_start_date)
    remove_column :venues, :festival_end_date if column_exists?(:venues, :festival_end_date)
    remove_column :venues, :festival_metadata if column_exists?(:venues, :festival_metadata)
  end

  private

  def add_festival_source_columns_to_venues
    return unless table_exists?(:venues)

    add_column :venues, :external_source, :string unless column_exists?(:venues, :external_source)
    add_column :venues, :external_source_url, :text unless column_exists?(:venues, :external_source_url)
    add_column :venues, :external_source_id, :string unless column_exists?(:venues, :external_source_id)
    add_column :venues, :source_fingerprint, :string unless column_exists?(:venues, :source_fingerprint)
    add_column :venues, :festival_start_date, :date unless column_exists?(:venues, :festival_start_date)
    add_column :venues, :festival_end_date, :date unless column_exists?(:venues, :festival_end_date)
    add_column :venues, :festival_metadata, :json unless column_exists?(:venues, :festival_metadata)

    unless index_exists?(:venues, [:external_source, :external_source_id], name: 'idx_venues_external_source_id')
      add_index :venues, [:external_source, :external_source_id], name: 'idx_venues_external_source_id'
    end
    add_index :venues, :source_fingerprint, name: 'idx_venues_source_fingerprint' unless index_exists?(:venues, :source_fingerprint, name: 'idx_venues_source_fingerprint')
    unless index_exists?(:venues, [:festival_start_date, :festival_end_date], name: 'idx_venues_festival_dates')
      add_index :venues, [:festival_start_date, :festival_end_date], name: 'idx_venues_festival_dates'
    end
  end

  def create_festival_import_runs
    return if table_exists?(:black_coffee_festival_import_runs)

    create_table :black_coffee_festival_import_runs do |t|
      t.string :source, null: false, default: 'fanmusicfest'
      t.string :status, null: false, default: 'pending'
      t.string :mode, null: false, default: 'dry_run'
      t.text :source_url
      t.integer :max_pages, null: false, default: 1
      t.integer :max_details, null: false, default: 0
      t.decimal :request_delay_seconds, precision: 6, scale: 2, null: false, default: 10.0
      t.string :strict_country_code, null: false, default: 'ES'
      t.boolean :import_details, null: false, default: false
      t.boolean :auto_publish, null: false, default: false
      t.bigint :created_by_id
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :robots_requests_count, null: false, default: 0
      t.integer :listing_requests_count, null: false, default: 0
      t.integer :detail_requests_count, null: false, default: 0
      t.integer :candidates_found_count, null: false, default: 0
      t.integer :outside_country_skipped_count, null: false, default: 0
      t.integer :duplicate_skipped_count, null: false, default: 0
      t.integer :invalid_skipped_count, null: false, default: 0
      t.integer :items_created_count, null: false, default: 0
      t.integer :venues_created_count, null: false, default: 0
      t.integer :venues_updated_count, null: false, default: 0
      t.integer :needs_review_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.json :summary_payload
      t.text :error_message
      t.timestamps
    end

    add_index :black_coffee_festival_import_runs, :status, name: 'idx_bc_festival_runs_status'
    add_index :black_coffee_festival_import_runs, :source, name: 'idx_bc_festival_runs_source'
    add_index :black_coffee_festival_import_runs, :created_at, name: 'idx_bc_festival_runs_created_at'
    add_index :black_coffee_festival_import_runs, :created_by_id, name: 'idx_bc_festival_runs_created_by'
    add_foreign_key :black_coffee_festival_import_runs,
                    :users,
                    column: :created_by_id,
                    name: 'fk_bc_festival_runs_created_by',
                    on_delete: :nullify
  end

  def create_festival_import_items
    return if table_exists?(:black_coffee_festival_import_items)

    create_table :black_coffee_festival_import_items do |t|
      t.references :black_coffee_festival_import_run,
                   null: false,
                   foreign_key: true,
                   index: { name: 'idx_bc_festival_items_run' }
      t.string :venue_id
      t.string :status, null: false, default: 'pending'
      t.string :source, null: false, default: 'fanmusicfest'
      t.text :source_url
      t.string :source_event_id
      t.string :fingerprint
      t.string :name
      t.string :city
      t.string :state
      t.string :country
      t.string :country_code
      t.date :start_date
      t.date :end_date
      t.text :image_url
      t.text :error_message
      t.json :raw_payload
      t.json :normalized_payload
      t.timestamps
    end

    add_index :black_coffee_festival_import_items, :venue_id, name: 'idx_bc_festival_items_venue'
    add_index :black_coffee_festival_import_items, :status, name: 'idx_bc_festival_items_status'
    add_index :black_coffee_festival_import_items, :source_event_id, name: 'idx_bc_festival_items_source_event'
    add_index :black_coffee_festival_import_items, :fingerprint, name: 'idx_bc_festival_items_fingerprint'
    add_index :black_coffee_festival_import_items, :country_code, name: 'idx_bc_festival_items_country'
    add_foreign_key :black_coffee_festival_import_items,
                    :venues,
                    column: :venue_id,
                    name: 'fk_bc_festival_items_venue',
                    on_delete: :nullify
  end
end
