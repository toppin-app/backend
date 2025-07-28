class CreateVipToppins < ActiveRecord::Migration[6.0]
  def change
    create_table :vip_toppins do |t|
      t.references :user, null: false, foreign_key: true
      t.date :week_start, null: false
      t.timestamps
    end
    add_index :vip_toppins, [:week_start]
  end
end