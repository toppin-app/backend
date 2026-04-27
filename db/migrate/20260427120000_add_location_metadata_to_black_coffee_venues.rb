class AddLocationMetadataToBlackCoffeeVenues < ActiveRecord::Migration[6.0]
  def up
    add_venue_location_columns
    add_candidate_location_columns
    backfill_existing_venues
  end

  def down
    remove_column :black_coffee_import_candidates, :country_code if column_exists?(:black_coffee_import_candidates, :country_code)
    remove_column :black_coffee_import_candidates, :country if column_exists?(:black_coffee_import_candidates, :country)
    remove_column :black_coffee_import_candidates, :state if column_exists?(:black_coffee_import_candidates, :state)
    remove_column :black_coffee_import_candidates, :postal_code if column_exists?(:black_coffee_import_candidates, :postal_code)

    remove_index :venues, name: 'idx_venues_country_code' if index_exists?(:venues, :country_code, name: 'idx_venues_country_code')
    remove_column :venues, :country_code if column_exists?(:venues, :country_code)
    remove_column :venues, :country if column_exists?(:venues, :country)
    remove_column :venues, :state if column_exists?(:venues, :state)
    remove_column :venues, :postal_code if column_exists?(:venues, :postal_code)
  end

  private

  def add_venue_location_columns
    add_column :venues, :postal_code, :string unless column_exists?(:venues, :postal_code)
    add_column :venues, :state, :string unless column_exists?(:venues, :state)
    add_column :venues, :country, :string unless column_exists?(:venues, :country)
    add_column :venues, :country_code, :string unless column_exists?(:venues, :country_code)
    add_column :venues, :google_place_id, :string unless column_exists?(:venues, :google_place_id)

    add_index :venues, :country_code, name: 'idx_venues_country_code' unless index_exists?(:venues, :country_code, name: 'idx_venues_country_code')
    add_index :venues, :google_place_id, unique: true, name: 'idx_venues_google_place_id' unless index_exists?(:venues, :google_place_id, name: 'idx_venues_google_place_id')
  end

  def add_candidate_location_columns
    return unless table_exists?(:black_coffee_import_candidates)

    add_column :black_coffee_import_candidates, :postal_code, :string unless column_exists?(:black_coffee_import_candidates, :postal_code)
    add_column :black_coffee_import_candidates, :state, :string unless column_exists?(:black_coffee_import_candidates, :state)
    add_column :black_coffee_import_candidates, :country, :string unless column_exists?(:black_coffee_import_candidates, :country)
    add_column :black_coffee_import_candidates, :country_code, :string unless column_exists?(:black_coffee_import_candidates, :country_code)
  end

  def backfill_existing_venues
    venue_record = Class.new(ActiveRecord::Base) do
      self.table_name = 'venues'
    end
    venue_record.reset_column_information

    venue_record.where(country: [nil, '']).update_all(country: 'Espana', country_code: 'ES')
    venue_record.where(city: 'Paterna').where(state: [nil, '']).update_all(state: 'Comunidad Valenciana', postal_code: '46980')
  end
end
