class AddShowPubliToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :show_publi, :boolean, default: true
  end
end
