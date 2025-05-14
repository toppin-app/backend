class UserFilterPreference < ApplicationRecord
  belongs_to :user
  enum gender: {female: 0, male: 1, gender_any: 2, couple: 3}
end
 