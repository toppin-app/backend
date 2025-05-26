class UserFilterPreference < ApplicationRecord
  belongs_to :user

  def gender_preferences_array
    gender_preferences&.split(',')&.map(&:strip) || []
  end
end

