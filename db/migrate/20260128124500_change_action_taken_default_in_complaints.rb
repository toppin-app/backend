class ChangeActionTakenDefaultInComplaints < ActiveRecord::Migration[6.0]
  def up
    change_column_default :complaints, :action_taken, from: 'none', to: 'no_action'
    execute "UPDATE complaints SET action_taken = 'no_action' WHERE action_taken = 'none'"
  end

  def down
    execute "UPDATE complaints SET action_taken = 'none' WHERE action_taken = 'no_action'"
    change_column_default :complaints, :action_taken, from: 'no_action', to: 'none'
  end
end
