class AddMatchDateToUserMatchRequests < ActiveRecord::Migration[6.0]
  def change
    add_column :user_match_requests, :match_date, :datetime
  end
end
