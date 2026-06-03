class CreateBlackCoffeeImageInternalizationBatches < ActiveRecord::Migration[6.0]
  def change
    return if table_exists?(:black_coffee_image_internalization_batches)

    create_table :black_coffee_image_internalization_batches do |t|
      t.string :status, null: false, default: 'pending'
      t.integer :total_venues, null: false, default: 0
      t.integer :processed_venues, null: false, default: 0
      t.integer :total_images, null: false, default: 0
      t.integer :processed_images, null: false, default: 0
      t.integer :converted_images_count, null: false, default: 0
      t.integer :converted_venues_count, null: false, default: 0
      t.integer :failed_images_count, null: false, default: 0
      t.integer :failed_venues_count, null: false, default: 0
      t.integer :skipped_images_count, null: false, default: 0
      t.bigint :created_by_id
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.json :report_payload
      t.timestamps
    end

    add_index :black_coffee_image_internalization_batches,
              :status,
              name: 'idx_bc_image_internalization_batches_status'
    add_index :black_coffee_image_internalization_batches,
              :created_at,
              name: 'idx_bc_image_internalization_batches_created_at'
    add_index :black_coffee_image_internalization_batches,
              :created_by_id,
              name: 'idx_bc_image_internalization_batches_created_by'
    add_foreign_key :black_coffee_image_internalization_batches,
                    :users,
                    column: :created_by_id,
                    name: 'fk_bc_image_internalization_batches_created_by',
                    on_delete: :nullify

    create_table :black_coffee_image_internalization_items do |t|
      t.bigint :black_coffee_image_internalization_batch_id, null: false
      t.string :venue_id, null: false
      t.bigint :venue_image_id
      t.string :venue_name
      t.text :source_url
      t.string :status, null: false, default: 'pending'
      t.string :content_type
      t.bigint :file_size
      t.integer :http_status
      t.string :error_type
      t.text :error_message
      t.datetime :processed_at
      t.timestamps
    end

    add_index :black_coffee_image_internalization_items,
              :black_coffee_image_internalization_batch_id,
              name: 'idx_bc_image_internalization_items_batch'
    add_index :black_coffee_image_internalization_items,
              :venue_id,
              name: 'idx_bc_image_internalization_items_venue'
    add_index :black_coffee_image_internalization_items,
              :venue_image_id,
              name: 'idx_bc_image_internalization_items_image'
    add_index :black_coffee_image_internalization_items,
              :status,
              name: 'idx_bc_image_internalization_items_status'
    add_index :black_coffee_image_internalization_items,
              :error_type,
              name: 'idx_bc_image_internalization_items_error_type'
    add_foreign_key :black_coffee_image_internalization_items,
                    :black_coffee_image_internalization_batches,
                    column: :black_coffee_image_internalization_batch_id,
                    name: 'fk_bc_image_internalization_items_batch',
                    on_delete: :cascade
    add_foreign_key :black_coffee_image_internalization_items,
                    :venues,
                    column: :venue_id,
                    name: 'fk_bc_image_internalization_items_venue',
                    on_delete: :cascade
    add_foreign_key :black_coffee_image_internalization_items,
                    :venue_images,
                    column: :venue_image_id,
                    name: 'fk_bc_image_internalization_items_image',
                    on_delete: :nullify
  end
end
