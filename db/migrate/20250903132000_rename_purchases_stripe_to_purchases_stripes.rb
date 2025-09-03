class RenamePurchasesStripeToPurchasesStripes < ActiveRecord::Migration[6.0]
  def change
    rename_table :purchases_stripe, :purchases_stripes
  end
end