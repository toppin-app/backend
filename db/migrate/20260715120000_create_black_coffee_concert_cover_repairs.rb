class CreateBlackCoffeeConcertCoverRepairs < ActiveRecord::Migration[6.0]
  def up
    create_cover_repair_batches
    create_cover_repair_items
    add_import_metrics
  end

  def down
    remove_import_metrics
    drop_table :black_coffee_concert_cover_repair_items if table_exists?(:black_coffee_concert_cover_repair_items)
    drop_table :black_coffee_concert_cover_repair_batches if table_exists?(:black_coffee_concert_cover_repair_batches)
  end

  private

  def create_cover_repair_batches
    return if table_exists?(:black_coffee_concert_cover_repair_batches)

    create_table :black_coffee_concert_cover_repair_batches do |t|
      t.string :status, null: false, default: 'pending'
      t.string :review_status_filter, null: false, default: 'approved'
      t.boolean :external_search_enabled, null: false, default: false
      t.integer :total_venues, null: false, default: 0
      t.integer :processed_venues, null: false, default: 0
      t.integer :source_recovered_count, null: false, default: 0
      t.integer :search_recovered_count, null: false, default: 0
      t.integer :rejected_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.integer :source_requests_count, null: false, default: 0
      t.integer :search_requests_count, null: false, default: 0
      t.integer :image_requests_count, null: false, default: 0
      t.bigint :created_by_id
      t.string :worker_token
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :last_worker_heartbeat_at
      t.text :error_message
      t.json :report_payload
      t.timestamps
    end

    add_index :black_coffee_concert_cover_repair_batches, :status, name: 'idx_bc_concert_cover_batches_status'
    add_index :black_coffee_concert_cover_repair_batches, :created_at, name: 'idx_bc_concert_cover_batches_created'
    add_index :black_coffee_concert_cover_repair_batches, :created_by_id, name: 'idx_bc_concert_cover_batches_user'
    add_foreign_key :black_coffee_concert_cover_repair_batches,
                    :users,
                    column: :created_by_id,
                    name: 'fk_bc_concert_cover_batches_user',
                    on_delete: :nullify
  end

  def create_cover_repair_items
    return if table_exists?(:black_coffee_concert_cover_repair_items)

    create_table :black_coffee_concert_cover_repair_items do |t|
      t.references :black_coffee_concert_cover_repair_batch,
                   null: false,
                   foreign_key: true,
                   index: { name: 'idx_bc_concert_cover_items_batch' }
      t.string :venue_id
      t.string :venue_name
      t.string :status, null: false, default: 'pending'
      t.string :original_review_status
      t.string :resolution_source
      t.text :source_page_url
      t.text :selected_image_url
      t.text :result_page_url
      t.decimal :confidence, precision: 5, scale: 2
      t.json :evidence
      t.string :error_type
      t.text :error_message
      t.datetime :processed_at
      t.timestamps
    end

    add_index :black_coffee_concert_cover_repair_items,
              [:black_coffee_concert_cover_repair_batch_id, :venue_id],
              unique: true,
              name: 'idx_bc_concert_cover_items_batch_venue'
    add_index :black_coffee_concert_cover_repair_items, :status, name: 'idx_bc_concert_cover_items_status'
    add_index :black_coffee_concert_cover_repair_items, :venue_id, name: 'idx_bc_concert_cover_items_venue'
    add_foreign_key :black_coffee_concert_cover_repair_items,
                    :venues,
                    column: :venue_id,
                    name: 'fk_bc_concert_cover_items_venue',
                    on_delete: :nullify
  end

  def add_import_metrics
    return unless table_exists?(:black_coffee_concert_import_runs)

    add_column :black_coffee_concert_import_runs, :source_cover_recovered_count, :integer, null: false, default: 0 unless column_exists?(:black_coffee_concert_import_runs, :source_cover_recovered_count)
    add_column :black_coffee_concert_import_runs, :search_cover_recovered_count, :integer, null: false, default: 0 unless column_exists?(:black_coffee_concert_import_runs, :search_cover_recovered_count)
    add_column :black_coffee_concert_import_runs, :no_cover_skipped_count, :integer, null: false, default: 0 unless column_exists?(:black_coffee_concert_import_runs, :no_cover_skipped_count)
    add_column :black_coffee_concert_import_runs, :image_search_requests_count, :integer, null: false, default: 0 unless column_exists?(:black_coffee_concert_import_runs, :image_search_requests_count)
    add_column :black_coffee_concert_import_runs, :image_download_requests_count, :integer, null: false, default: 0 unless column_exists?(:black_coffee_concert_import_runs, :image_download_requests_count)

    return unless table_exists?(:black_coffee_concert_import_items)

    add_column :black_coffee_concert_import_items, :image_resolution_source, :string unless column_exists?(:black_coffee_concert_import_items, :image_resolution_source)
    add_column :black_coffee_concert_import_items, :image_resolution_confidence, :decimal, precision: 5, scale: 2 unless column_exists?(:black_coffee_concert_import_items, :image_resolution_confidence)
    add_column :black_coffee_concert_import_items, :image_resolution_evidence, :json unless column_exists?(:black_coffee_concert_import_items, :image_resolution_evidence)
  end

  def remove_import_metrics
    if table_exists?(:black_coffee_concert_import_items)
      remove_column :black_coffee_concert_import_items, :image_resolution_source if column_exists?(:black_coffee_concert_import_items, :image_resolution_source)
      remove_column :black_coffee_concert_import_items, :image_resolution_confidence if column_exists?(:black_coffee_concert_import_items, :image_resolution_confidence)
      remove_column :black_coffee_concert_import_items, :image_resolution_evidence if column_exists?(:black_coffee_concert_import_items, :image_resolution_evidence)
    end

    return unless table_exists?(:black_coffee_concert_import_runs)

    remove_column :black_coffee_concert_import_runs, :source_cover_recovered_count if column_exists?(:black_coffee_concert_import_runs, :source_cover_recovered_count)
    remove_column :black_coffee_concert_import_runs, :search_cover_recovered_count if column_exists?(:black_coffee_concert_import_runs, :search_cover_recovered_count)
    remove_column :black_coffee_concert_import_runs, :no_cover_skipped_count if column_exists?(:black_coffee_concert_import_runs, :no_cover_skipped_count)
    remove_column :black_coffee_concert_import_runs, :image_search_requests_count if column_exists?(:black_coffee_concert_import_runs, :image_search_requests_count)
    remove_column :black_coffee_concert_import_runs, :image_download_requests_count if column_exists?(:black_coffee_concert_import_runs, :image_download_requests_count)
  end
end
