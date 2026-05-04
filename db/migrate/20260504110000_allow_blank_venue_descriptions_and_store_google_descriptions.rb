class AllowBlankVenueDescriptionsAndStoreGoogleDescriptions < ActiveRecord::Migration[6.0]
  def up
    add_column :black_coffee_import_candidates, :google_description, :text unless column_exists?(:black_coffee_import_candidates, :google_description)
    add_column :black_coffee_import_candidates, :google_description_language_code, :string unless column_exists?(:black_coffee_import_candidates, :google_description_language_code)

    change_column_null :venues, :description, true if column_exists?(:venues, :description)
  end

  def down
    change_column_null :venues, :description, false if column_exists?(:venues, :description)

    remove_column :black_coffee_import_candidates, :google_description_language_code if column_exists?(:black_coffee_import_candidates, :google_description_language_code)
    remove_column :black_coffee_import_candidates, :google_description if column_exists?(:black_coffee_import_candidates, :google_description)
  end
end
