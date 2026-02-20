class AddLocationToBannerUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :banner_users, :locality, :string
    add_column :banner_users, :country, :string
    add_column :banner_users, :lat, :string
    add_column :banner_users, :lng, :string
  end
end
