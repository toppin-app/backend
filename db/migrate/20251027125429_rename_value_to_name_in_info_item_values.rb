class RenameValueToNameInInfoItemValues < ActiveRecord::Migration[6.0]
  def change
    rename_column :info_item_values, :value, :name
  end
end
