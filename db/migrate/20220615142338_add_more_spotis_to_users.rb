class AddMoreSpotisToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :spoty5, :string
    add_column :users, :spoty_title5, :string
    add_column :users, :spoty6, :string
    add_column :users, :spoty_title6, :string
  end
end
