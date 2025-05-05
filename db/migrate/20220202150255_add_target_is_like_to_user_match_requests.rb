class AddTargetIsLikeToUserMatchRequests < ActiveRecord::Migration[6.0]
  def change
    add_column :user_match_requests, :target_is_like, :boolean, default: false
  end
end
