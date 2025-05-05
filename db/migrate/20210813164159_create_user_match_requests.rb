class CreateUserMatchRequests < ActiveRecord::Migration[6.0]
  def change
    create_table :user_match_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :target_user
      t.boolean :is_match, :default => false
      t.boolean :is_paid, :default => false
      t.boolean :is_rejected, :default => false
      t.integer :affinity_index

      t.timestamps
    end
  end
end
