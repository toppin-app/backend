class AddFieldsToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :name, :string
    add_column :users, :lastname, :string
    add_column :users, :role, :string
    add_column :users, :department, :string
    add_column :users, :position, :string
    add_column :users, :signature, :string
    add_column :users, :image, :string
  end
end
