class CreateVideoCalls < ActiveRecord::Migration[6.0]
  def change
    create_table :video_calls do |t|
      t.references :user_1, null: false, foreign_key: { to_table: :users }
      t.references :user_2, null: false, foreign_key: { to_table: :users }

      t.string :agora_channel_name, null: false
      t.integer :status, null: false, default: 0  # 0: pending, 1: active, 2: ended

      t.datetime :started_at
      t.datetime :ended_at
      t.integer :duration

      t.timestamps
    end

    add_index :video_calls, :agora_channel_name, unique: true
  end
end
# This migration creates the video_calls table with references to two users,
# an Agora channel name, and fields for status, timestamps, and duration.