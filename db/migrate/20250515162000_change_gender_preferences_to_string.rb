class ChangeGenderPreferencesToString < ActiveRecord::Migration[6.0]
  def change
    change_column :user_filter_preferences, :gender_preferences, :string
  end
end