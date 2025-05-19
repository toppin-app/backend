# db/migrate/20250519120000_add_gender_preferences_to_user_filter_preferences.rb
class AddGenderPreferencesToUserFilterPreferences < ActiveRecord::Migration[6.0]
  def change
    change_column :user_filter_preferences, :gender_preferences, :text
  end
end
