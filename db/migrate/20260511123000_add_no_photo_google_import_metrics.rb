class AddNoPhotoGoogleImportMetrics < ActiveRecord::Migration[6.0]
  def change
    add_column_unless_exists :black_coffee_import_runs, :no_photo_skipped_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_imports, :no_photo_skipped_count, :integer, null: false, default: 0
    add_column_unless_exists :black_coffee_bulk_import_steps, :no_photo_skipped_count, :integer, null: false, default: 0
  end

  private

  def add_column_unless_exists(table, column, type, **options)
    add_column(table, column, type, **options) unless column_exists?(table, column)
  end
end
