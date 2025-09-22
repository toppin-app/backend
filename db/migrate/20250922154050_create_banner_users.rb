class CreateBannerUsers < ActiveRecord::Migration[6.0]
  def change
    create_table :banner_users do |t|
      t.references :banner, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :viewed, default: true, null: false
      t.datetime :viewed_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      
      t.timestamps
    end

    add_index :banner_users, [:user_id, :banner_id], unique: true
    add_index :banner_users, :viewed_at
  end
end