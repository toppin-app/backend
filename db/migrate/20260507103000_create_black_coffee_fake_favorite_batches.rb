class CreateBlackCoffeeFakeFavoriteBatches < ActiveRecord::Migration[6.0]
  def change
    create_table :black_coffee_fake_favorite_batches do |t|
      t.string :status, null: false, default: 'pending'
      t.json :user_ids_payload
      t.json :pending_user_ids_payload
      t.json :failed_user_ids_payload
      t.json :states_payload
      t.json :categories_payload
      t.json :combination_entries_payload
      t.json :empty_combinations_payload
      t.integer :total_users_count, null: false, default: 0
      t.integer :pending_users_count, null: false, default: 0
      t.integer :processed_users_count, null: false, default: 0
      t.integer :failed_users_count, null: false, default: 0
      t.integer :deleted_favorites_count, null: false, default: 0
      t.integer :created_favorites_count, null: false, default: 0
      t.integer :combinations_count, null: false, default: 0
      t.integer :combinations_without_venues_count, null: false, default: 0
      t.bigint :current_user_id
      t.string :current_user_name
      t.bigint :last_processed_user_id
      t.string :last_processed_user_name
      t.datetime :favorites_reset_at
      t.datetime :started_at
      t.datetime :last_advanced_at
      t.datetime :finished_at
      t.text :error_message
      t.timestamps
    end

    add_index :black_coffee_fake_favorite_batches, :status, name: 'idx_bc_fake_favorite_batches_status'
  end
end
