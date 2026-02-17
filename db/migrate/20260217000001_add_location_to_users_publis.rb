class AddLocationToUsersPublis < ActiveRecord::Migration[6.0]
  def change
    add_column :users_publis, :locality, :string
    add_column :users_publis, :country, :string
    add_column :users_publis, :lat, :string
    add_column :users_publis, :lng, :string
  end
end
