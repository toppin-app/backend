class CreateBlackCoffeeImageAuditBatches < ActiveRecord::Migration[6.0]
  def change
    return if table_exists?(:black_coffee_image_audit_batches)

    create_table :black_coffee_image_audit_batches do |t|
      t.string :status, null: false, default: 'pending'
      t.integer :total_venues, null: false, default: 0
      t.integer :processed_venues, null: false, default: 0
      t.integer :total_images, null: false, default: 0
      t.integer :checked_images, null: false, default: 0
      t.integer :failed_venues_count, null: false, default: 0
      t.integer :failed_images_count, null: false, default: 0
      t.integer :rejected_venues_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :rejected_at
      t.bigint :rejected_by_id
      t.text :error_message
      t.json :report_payload
      t.timestamps
    end

    add_index :black_coffee_image_audit_batches, :status, name: 'idx_bc_image_audit_batches_status'
    add_index :black_coffee_image_audit_batches, :created_at, name: 'idx_bc_image_audit_batches_created_at'
    add_index :black_coffee_image_audit_batches, :rejected_by_id, name: 'idx_bc_image_audit_batches_rejected_by'
    add_foreign_key :black_coffee_image_audit_batches,
                    :users,
                    column: :rejected_by_id,
                    name: 'fk_bc_image_audit_batches_rejected_by',
                    on_delete: :nullify

    create_table :black_coffee_image_audit_items do |t|
      t.bigint :black_coffee_image_audit_batch_id, null: false
      t.string :venue_id, null: false
      t.bigint :venue_image_id
      t.string :venue_name
      t.text :image_url
      t.string :status, null: false, default: 'pending'
      t.string :error_type
      t.integer :http_status
      t.text :error_message
      t.datetime :checked_at
      t.timestamps
    end

    add_index :black_coffee_image_audit_items,
              :black_coffee_image_audit_batch_id,
              name: 'idx_bc_image_audit_items_batch'
    add_index :black_coffee_image_audit_items, :venue_id, name: 'idx_bc_image_audit_items_venue'
    add_index :black_coffee_image_audit_items, :status, name: 'idx_bc_image_audit_items_status'
    add_index :black_coffee_image_audit_items, :error_type, name: 'idx_bc_image_audit_items_error_type'
    add_foreign_key :black_coffee_image_audit_items,
                    :black_coffee_image_audit_batches,
                    column: :black_coffee_image_audit_batch_id,
                    name: 'fk_bc_image_audit_items_batch',
                    on_delete: :cascade
    add_foreign_key :black_coffee_image_audit_items,
                    :venues,
                    column: :venue_id,
                    name: 'fk_bc_image_audit_items_venue',
                    on_delete: :cascade
  end
end
