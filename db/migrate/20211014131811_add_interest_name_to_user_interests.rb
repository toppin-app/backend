class AddInterestNameToUserInterests < ActiveRecord::Migration[6.0]
  def change
    add_column :user_interests, :interest_name, :string
  end
end
