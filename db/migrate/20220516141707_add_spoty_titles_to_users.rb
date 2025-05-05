class AddSpotyTitlesToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :spoty_title1, :string
    add_column :users, :spoty_title2, :string
    add_column :users, :spoty_title3, :string
    add_column :users, :spoty_title4, :string
  end
end
