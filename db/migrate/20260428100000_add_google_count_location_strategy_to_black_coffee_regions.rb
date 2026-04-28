class AddGoogleCountLocationStrategyToBlackCoffeeRegions < ActiveRecord::Migration[6.0]
  def change
    return unless table_exists?(:black_coffee_import_regions)

    unless column_exists?(:black_coffee_import_regions, :google_count_location_strategy)
      add_column :black_coffee_import_regions, :google_count_location_strategy, :string, default: 'region', null: false
    end

    unless column_exists?(:black_coffee_import_regions, :google_count_location_note)
      add_column :black_coffee_import_regions, :google_count_location_note, :text
    end
  end
end
