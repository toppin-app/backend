class CreateUserVipUnlocks < ActiveRecord::Migration[6.0]
  def change
    create_table :user_vip_unlocks do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :target_id

      t.timestamps
    end
  end
end
