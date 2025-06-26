class RemoveUniqueIndexFromAgoraChannelName < ActiveRecord::Migration[6.0]
  # This migration removes the unique index from the agora_channel_name column
  # in the video_calls table, allowing for non-unique values.
  def change
    remove_index :video_calls, :agora_channel_name
    add_index :video_calls, :agora_channel_name # sin unique: true
  end
end