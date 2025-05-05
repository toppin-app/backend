class AddIsSugarSweetToUserMatchRequests < ActiveRecord::Migration[6.0]
  def change
    add_column :user_match_requests, :is_sugar_sweet, :boolean, default: false
  end
end
