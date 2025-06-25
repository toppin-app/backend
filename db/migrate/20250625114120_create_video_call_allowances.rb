class CreateVideoCallAllowances < ActiveRecord::Migration[6.0]
  def change
    create_table :video_call_allowances do |t|
      t.integer :user_1_id, null: false
      t.integer :user_2_id, null: false
      t.integer :seconds_used, default: 0, null: false

      t.timestamps
    end

    add_index :video_call_allowances, [:user_1_id, :user_2_id], unique: true
  end
end