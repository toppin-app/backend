class AddDescriptionToPublis < ActiveRecord::Migration[6.0]
  def change
    add_column :publis, :description, :text
  end
end