class AddBlockReasonKeyToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :block_reason_key, :string
  end
end
