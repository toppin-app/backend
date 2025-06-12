class AddLanguageToUsers < ActiveRecord::Migration[6.0] # o tu versión actual
  def change
    add_column :users, :language, :integer, default: 0, null: false
  end
end
