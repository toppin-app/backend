class AddLastLikeGivenToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :last_like_given, :datetime
  end
end
