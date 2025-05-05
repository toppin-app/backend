class AddIncomingMatchRequestNumberToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :incoming_match_request_number, :integer, default: 0
  end
end
