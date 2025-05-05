class AddAdditionalFieldsToUserFilterPreferences < ActiveRecord::Migration[6.0]
  def change
    add_column :user_filter_preferences, :only_verified_users, :boolean
    add_column :user_filter_preferences, :interests, :string
    add_column :user_filter_preferences, :categories, :string
  end
end
