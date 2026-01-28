class AddStatusAndActionToComplaints < ActiveRecord::Migration[6.0]
  def change
    add_column :complaints, :status, :string, default: 'unreviewed', null: false
    add_column :complaints, :action_taken, :string, default: 'no_action', null: false

    add_index :complaints, :status
    add_index :complaints, :action_taken
  end
end
