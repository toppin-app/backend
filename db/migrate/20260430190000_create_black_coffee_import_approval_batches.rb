class CreateBlackCoffeeImportApprovalBatches < ActiveRecord::Migration[6.0]
  def change
    create_table :black_coffee_import_approval_batches do |t|
      t.references :black_coffee_import_run,
                   null: false,
                   foreign_key: true,
                   index: { name: 'idx_bc_import_approval_batches_run' }
      t.string :status, null: false, default: 'pending'
      t.string :selection_mode, null: false, default: 'selected_ids'
      t.json :candidate_ids_payload
      t.json :pending_candidate_ids_payload
      t.json :failed_candidate_ids_payload
      t.integer :total_candidates_count, null: false, default: 0
      t.integer :pending_candidates_count, null: false, default: 0
      t.integer :processed_candidates_count, null: false, default: 0
      t.integer :approved_candidates_count, null: false, default: 0
      t.integer :duplicate_candidates_count, null: false, default: 0
      t.integer :skipped_candidates_count, null: false, default: 0
      t.integer :failed_candidates_count, null: false, default: 0
      t.bigint :last_processed_candidate_id
      t.bigint :current_candidate_id
      t.string :current_candidate_name
      t.datetime :started_at
      t.datetime :last_advanced_at
      t.datetime :finished_at
      t.text :error_message

      t.timestamps
    end

    add_index :black_coffee_import_approval_batches, :status, name: 'idx_bc_import_approval_batches_status'
    add_index :black_coffee_import_approval_batches,
              [:black_coffee_import_run_id, :status],
              name: 'idx_bc_import_approval_batches_run_status'

    add_index :black_coffee_import_candidates,
              [:black_coffee_import_run_id, :status, :id],
              name: 'idx_bc_candidates_run_status_id'
  end
end
