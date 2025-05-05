class AddNewFieldsToUserMatchRequests < ActiveRecord::Migration[6.0]
  def change
    add_column :user_match_requests, :is_like, :boolean
    add_column :user_match_requests, :is_superlike, :boolean
  end
end
