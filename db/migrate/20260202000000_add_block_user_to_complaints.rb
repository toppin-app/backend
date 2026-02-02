class AddBlockUserToComplaints < ActiveRecord::Migration[6.0]
  def change
    add_column :complaints, :block_user, :boolean, default: false
  end
end
