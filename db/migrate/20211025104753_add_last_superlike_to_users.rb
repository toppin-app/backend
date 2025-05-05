class AddLastSuperlikeToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :last_superlike_given, :datetime
  end
end
