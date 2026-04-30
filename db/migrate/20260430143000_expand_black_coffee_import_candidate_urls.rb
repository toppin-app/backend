class ExpandBlackCoffeeImportCandidateUrls < ActiveRecord::Migration[6.0]
  def up
    change_column :black_coffee_import_candidates, :website, :text
    change_column :black_coffee_import_candidates, :google_maps_uri, :text
  end

  def down
    change_column :black_coffee_import_candidates, :website, :string
    change_column :black_coffee_import_candidates, :google_maps_uri, :string
  end
end
