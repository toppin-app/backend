class AddCurrentConversationToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :current_conversation, :string
  end
end
