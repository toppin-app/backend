class UserFilterPreference < ApplicationRecord
  belongs_to :user

  enum gender: {female: 0, male: 1, all_gender_types: 2, couple: 3}
end
