class AddLocationCountryToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :location_country, :string
  end
end
