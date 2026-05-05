class AddGoogleTypeBreakdownToVenues < ActiveRecord::Migration[6.0]
  def change
    add_column :venues, :google_primary_type, :string unless column_exists?(:venues, :google_primary_type)
    add_column :venues, :google_secondary_types, :json unless column_exists?(:venues, :google_secondary_types)

    add_index :venues, :google_primary_type, name: 'idx_venues_google_primary_type' unless index_exists?(:venues, :google_primary_type, name: 'idx_venues_google_primary_type')
  end
end
