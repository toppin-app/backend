class RenameUserFilterPreferencesGenderToGenderPreference < ActiveRecord::Migration[6.0]
  def change
    rename_column :user_filter_preferences, :gender, :gender_preference
  end
end