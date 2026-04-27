class AddGoogleCountMetadataToBlackCoffeeImports < ActiveRecord::Migration[6.0]
  def change
    add_region_google_metadata
    add_region_category_google_totals
  end

  private

  def add_region_google_metadata
    return unless table_exists?(:black_coffee_import_regions)

    add_column :black_coffee_import_regions, :google_region_place_id, :string unless column_exists?(:black_coffee_import_regions, :google_region_place_id)
    add_column :black_coffee_import_regions, :google_region_place_id_resolved_at, :datetime unless column_exists?(:black_coffee_import_regions, :google_region_place_id_resolved_at)

    unless index_exists?(:black_coffee_import_regions, :google_region_place_id, name: 'idx_bc_regions_google_place')
      add_index :black_coffee_import_regions, :google_region_place_id, name: 'idx_bc_regions_google_place'
    end
  end

  def add_region_category_google_totals
    return unless table_exists?(:black_coffee_import_region_categories)

    add_column :black_coffee_import_region_categories, :google_total_count, :integer unless column_exists?(:black_coffee_import_region_categories, :google_total_count)
    add_column :black_coffee_import_region_categories, :google_total_counted_at, :datetime unless column_exists?(:black_coffee_import_region_categories, :google_total_counted_at)
    add_column :black_coffee_import_region_categories, :google_total_count_error, :text unless column_exists?(:black_coffee_import_region_categories, :google_total_count_error)
  end
end
