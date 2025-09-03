class RenameIncrementInPurchasesStripes < ActiveRecord::Migration[6.0]
  def change
    rename_column :purchases_stripes, :increment, :increment_value
  end
end