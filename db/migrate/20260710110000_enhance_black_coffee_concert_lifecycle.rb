class EnhanceBlackCoffeeConcertLifecycle < ActiveRecord::Migration[6.0]
  def up
    add_venue_event_columns
    add_concert_import_run_columns
    add_concert_import_item_columns
  end

  def down
    remove_index :venues, name: 'idx_venues_category_event_dedupe_unique' if index_exists?(:venues, [:category, :event_dedupe_key], name: 'idx_venues_category_event_dedupe_unique')
    remove_index :venues, name: 'idx_venues_category_event_status_start' if index_exists?(:venues, [:category, :event_status, :event_start_at], name: 'idx_venues_category_event_status_start')
    remove_index :venues, name: 'idx_venues_event_import_origin' if index_exists?(:venues, :event_import_origin, name: 'idx_venues_event_import_origin')

    remove_column :venues, :event_start_at if column_exists?(:venues, :event_start_at)
    remove_column :venues, :event_end_at if column_exists?(:venues, :event_end_at)
    remove_column :venues, :event_status if column_exists?(:venues, :event_status)
    remove_column :venues, :event_import_origin if column_exists?(:venues, :event_import_origin)
    remove_column :venues, :event_dedupe_key if column_exists?(:venues, :event_dedupe_key)

    remove_column :black_coffee_concert_import_runs, :import_origin if column_exists?(:black_coffee_concert_import_runs, :import_origin)
    remove_column :black_coffee_concert_import_runs, :non_concert_skipped_count if column_exists?(:black_coffee_concert_import_runs, :non_concert_skipped_count)
    remove_column :black_coffee_concert_import_runs, :occurred_marked_count if column_exists?(:black_coffee_concert_import_runs, :occurred_marked_count)

    remove_index :black_coffee_concert_import_items, name: 'idx_bc_concert_items_event_dedupe' if index_exists?(:black_coffee_concert_import_items, :event_dedupe_key, name: 'idx_bc_concert_items_event_dedupe')
    remove_column :black_coffee_concert_import_items, :start_at if column_exists?(:black_coffee_concert_import_items, :start_at)
    remove_column :black_coffee_concert_import_items, :end_at if column_exists?(:black_coffee_concert_import_items, :end_at)
    remove_column :black_coffee_concert_import_items, :event_dedupe_key if column_exists?(:black_coffee_concert_import_items, :event_dedupe_key)
  end

  private

  def add_venue_event_columns
    add_column :venues, :event_start_at, :datetime unless column_exists?(:venues, :event_start_at)
    add_column :venues, :event_end_at, :datetime unless column_exists?(:venues, :event_end_at)
    add_column :venues, :event_status, :string, null: false, default: 'upcoming' unless column_exists?(:venues, :event_status)
    add_column :venues, :event_import_origin, :string unless column_exists?(:venues, :event_import_origin)
    add_column :venues, :event_dedupe_key, :string unless column_exists?(:venues, :event_dedupe_key)

    unless index_exists?(:venues, [:category, :event_status, :event_start_at], name: 'idx_venues_category_event_status_start')
      add_index :venues, [:category, :event_status, :event_start_at], name: 'idx_venues_category_event_status_start'
    end

    add_index :venues, :event_import_origin, name: 'idx_venues_event_import_origin' unless index_exists?(:venues, :event_import_origin, name: 'idx_venues_event_import_origin')

    unless index_exists?(:venues, [:category, :event_dedupe_key], name: 'idx_venues_category_event_dedupe_unique')
      add_index :venues, [:category, :event_dedupe_key], unique: true, name: 'idx_venues_category_event_dedupe_unique'
    end
  end

  def add_concert_import_run_columns
    return unless table_exists?(:black_coffee_concert_import_runs)

    add_column :black_coffee_concert_import_runs, :import_origin, :string, null: false, default: 'dashboard' unless column_exists?(:black_coffee_concert_import_runs, :import_origin)
    add_column :black_coffee_concert_import_runs, :non_concert_skipped_count, :integer, null: false, default: 0 unless column_exists?(:black_coffee_concert_import_runs, :non_concert_skipped_count)
    add_column :black_coffee_concert_import_runs, :occurred_marked_count, :integer, null: false, default: 0 unless column_exists?(:black_coffee_concert_import_runs, :occurred_marked_count)
  end

  def add_concert_import_item_columns
    return unless table_exists?(:black_coffee_concert_import_items)

    add_column :black_coffee_concert_import_items, :start_at, :datetime unless column_exists?(:black_coffee_concert_import_items, :start_at)
    add_column :black_coffee_concert_import_items, :end_at, :datetime unless column_exists?(:black_coffee_concert_import_items, :end_at)
    add_column :black_coffee_concert_import_items, :event_dedupe_key, :string unless column_exists?(:black_coffee_concert_import_items, :event_dedupe_key)
    add_index :black_coffee_concert_import_items, :event_dedupe_key, name: 'idx_bc_concert_items_event_dedupe' unless index_exists?(:black_coffee_concert_import_items, :event_dedupe_key, name: 'idx_bc_concert_items_event_dedupe')
  end
end
