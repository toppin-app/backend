class AddRankingsToUserMatchRequests < ActiveRecord::Migration[6.0]
  def change
    add_column :user_match_requests, :user_ranking, :integer
    add_column :user_match_requests, :target_user_ranking, :integer
  end
end
