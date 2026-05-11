class AddGoogleImportCostControls < ActiveRecord::Migration[6.0]
  def change
    add_import_run_metrics
    add_bulk_import_metrics
    add_bulk_import_step_metrics
  end

  private

  def add_import_run_metrics
    add_column_unless_exists :black_coffee_import_runs, :raw_candidates_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_import_runs, :existing_skipped_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_import_runs, :outside_region_skipped_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_import_runs, :invalid_category_skipped_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_import_runs, :google_search_requests_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_import_runs, :google_details_requests_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_import_runs, :google_photo_requests_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_import_runs, :photo_references_saved_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_import_runs, :photo_urls_resolved_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_import_runs, :import_options, :json
  end

  def add_bulk_import_metrics
    add_column_unless_exists :black_coffee_bulk_imports, :existing_skipped_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_imports, :outside_region_skipped_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_imports, :invalid_category_skipped_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_imports, :google_photo_requests_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_imports, :photo_references_saved_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_imports, :photo_urls_resolved_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_imports, :import_options, :json
  end

  def add_bulk_import_step_metrics
    add_column_unless_exists :black_coffee_bulk_import_steps, :existing_skipped_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_import_steps, :outside_region_skipped_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_import_steps, :invalid_category_skipped_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_import_steps, :photo_requests_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_import_steps, :photo_references_saved_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_import_steps, :photo_urls_resolved_count, :integer, null: false, default: 0
  end

  def add_column_unless_exists(table, column, type, **options)
    add_column(table, column, type, **options) unless column_exists?(table, column)
  end
end
