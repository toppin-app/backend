class AddGoogleCountErrorDetailsToBlackCoffeeImports < ActiveRecord::Migration[6.0]
  def change
    return unless table_exists?(:black_coffee_import_region_categories)

    unless column_exists?(:black_coffee_import_region_categories, :google_total_count_error_details)
      add_column :black_coffee_import_region_categories, :google_total_count_error_details, :text
    end
  end
end
