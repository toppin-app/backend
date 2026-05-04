class CreateBlackCoffeeVenueGoogleSyncBatches < ActiveRecord::Migration[6.0]
  def change
    create_table :black_coffee_venue_google_sync_batches do |t|
      t.string :status, null: false, default: 'pending'
      t.string :selection_mode, null: false, default: 'selected_ids'
      t.json :venue_ids_payload
      t.json :pending_venue_ids_payload
      t.json :failed_venue_ids_payload
      t.integer :total_venues_count, null: false, default: 0
      t.integer :pending_venues_count, null: false, default: 0
      t.integer :processed_venues_count, null: false, default: 0
      t.integer :synced_venues_count, null: false, default: 0
      t.integer :skipped_venues_count, null: false, default: 0
      t.integer :failed_venues_count, null: false, default: 0
      t.integer :requests_count, null: false, default: 0
      t.string :current_venue_id
      t.string :current_venue_name
      t.string :last_processed_venue_id
      t.datetime :started_at
      t.datetime :last_advanced_at
      t.datetime :finished_at
      t.text :error_message

      t.timestamps
    end

    add_index :black_coffee_venue_google_sync_batches, :status, name: 'idx_bc_venue_google_sync_batches_status'
    add_index :black_coffee_venue_google_sync_batches, :selection_mode, name: 'idx_bc_venue_google_sync_batches_mode'
    add_index :black_coffee_venue_google_sync_batches, :created_at, name: 'idx_bc_venue_google_sync_batches_created_at'
  end
end
