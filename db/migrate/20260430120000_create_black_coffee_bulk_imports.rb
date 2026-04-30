class CreateBlackCoffeeBulkImports < ActiveRecord::Migration[6.0]
  def change
    create_table :black_coffee_bulk_imports do |t|
      t.references :black_coffee_import_region,
                   null: false,
                   foreign_key: true,
                   index: { name: 'idx_bc_bulk_imports_region' }
      t.string :status, null: false, default: 'pending'
      t.string :geometry_strategy
      t.json :categories_payload
      t.json :bounds_payload
      t.integer :max_depth, null: false, default: 8
      t.integer :min_cell_size_meters, null: false, default: 1_500
      t.integer :step_limit, null: false, default: 60
      t.integer :total_steps, null: false, default: 0
      t.integer :pending_steps_count, null: false, default: 0
      t.integer :running_steps_count, null: false, default: 0
      t.integer :completed_steps_count, null: false, default: 0
      t.integer :split_steps_count, null: false, default: 0
      t.integer :failed_steps_count, null: false, default: 0
      t.integer :saturated_steps_count, null: false, default: 0
      t.integer :completed_categories_count, null: false, default: 0
      t.integer :requests_count, null: false, default: 0
      t.integer :found_count, null: false, default: 0
      t.integer :saved_candidates_count, null: false, default: 0
      t.integer :duplicate_candidates_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.string :current_category
      t.string :current_cell_label
      t.datetime :started_at
      t.datetime :last_advanced_at
      t.datetime :finished_at
      t.text :error_message

      t.timestamps
    end

    add_index :black_coffee_bulk_imports, :status, name: 'idx_bc_bulk_imports_status'
    add_index :black_coffee_bulk_imports,
              [:black_coffee_import_region_id, :status],
              name: 'idx_bc_bulk_imports_region_status'

    create_table :black_coffee_bulk_import_steps do |t|
      t.references :black_coffee_bulk_import,
                   null: false,
                   foreign_key: true,
                   index: { name: 'idx_bc_bulk_steps_import' }
      t.references :black_coffee_import_run,
                   foreign_key: true,
                   index: { name: 'idx_bc_bulk_steps_run' }
      t.string :category, null: false
      t.string :status, null: false, default: 'pending'
      t.integer :depth, null: false, default: 0
      t.decimal :south_latitude, precision: 10, scale: 7, null: false
      t.decimal :south_longitude, precision: 10, scale: 7, null: false
      t.decimal :north_latitude, precision: 10, scale: 7, null: false
      t.decimal :north_longitude, precision: 10, scale: 7, null: false
      t.integer :found_count, null: false, default: 0
      t.integer :saved_count, null: false, default: 0
      t.integer :duplicate_count, null: false, default: 0
      t.integer :request_count, null: false, default: 0
      t.boolean :saturated, null: false, default: false
      t.datetime :processed_at
      t.text :error_message

      t.timestamps
    end

    add_index :black_coffee_bulk_import_steps, :status, name: 'idx_bc_bulk_steps_status'
    add_index :black_coffee_bulk_import_steps,
              [:black_coffee_bulk_import_id, :category, :status],
              name: 'idx_bc_bulk_steps_import_category_status'

    add_reference :black_coffee_import_runs,
                  :black_coffee_bulk_import,
                  foreign_key: true,
                  index: { name: 'idx_bc_import_runs_bulk_import' }
  end
end
