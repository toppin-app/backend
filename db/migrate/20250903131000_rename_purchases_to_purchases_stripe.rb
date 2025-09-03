class RenamePurchasesToPurchasesStripe < ActiveRecord::Migration[6.0]
  def change
    rename_table :purchases, :purchases_stripe
  end
end