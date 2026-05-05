class CreateBlackCoffeeGoogleImportFilters < ActiveRecord::Migration[6.0]
  def change
    create_table :black_coffee_google_import_filters do |t|
      t.string :category, null: false
      t.json :excluded_primary_types
      t.json :excluded_types
      t.json :excluded_keywords

      t.timestamps
    end

    add_index :black_coffee_google_import_filters,
              :category,
              unique: true,
              name: 'idx_bc_google_import_filters_category'
  end
end
