class AddLocationCityToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :location_city, :string
  end
end
