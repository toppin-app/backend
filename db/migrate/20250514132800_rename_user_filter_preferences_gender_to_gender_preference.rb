class RenameUserFilterPreferencesGenderToGenderPreference < ActiveRecord::Migration[6.0]
  def change
    rename_column :user_filter_preferences, :gender_preference, :gender_preferences
  end
end