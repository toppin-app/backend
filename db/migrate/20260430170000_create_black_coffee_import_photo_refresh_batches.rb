class CreateBlackCoffeeImportPhotoRefreshBatches < ActiveRecord::Migration[6.0]
  def change
    create_table :black_coffee_import_photo_refresh_batches do |t|
      t.references :black_coffee_import_run,
                   null: false,
                   foreign_key: true,
                   index: { name: 'idx_bc_photo_refresh_batches_run' }
      t.string :status, null: false, default: 'pending'
      t.json :candidate_ids_payload
      t.json :pending_candidate_ids_payload
      t.json :refreshed_candidate_ids_payload
      t.json :skipped_candidate_ids_payload
      t.json :failed_candidate_ids_payload
      t.integer :total_candidates_count, null: false, default: 0
      t.integer :pending_candidates_count, null: false, default: 0
      t.integer :processed_candidates_count, null: false, default: 0
      t.integer :refreshed_candidates_count, null: false, default: 0
      t.integer :skipped_candidates_count, null: false, default: 0
      t.integer :failed_candidates_count, null: false, default: 0
      t.integer :requests_count, null: false, default: 0
      t.bigint :current_candidate_id
      t.string :current_candidate_name
      t.datetime :started_at
      t.datetime :last_advanced_at
      t.datetime :finished_at
      t.text :error_message

      t.timestamps
    end

    add_index :black_coffee_import_photo_refresh_batches, :status, name: 'idx_bc_photo_refresh_batches_status'
  end
end
