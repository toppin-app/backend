class Interest < ApplicationRecord
  has_many :user_main_interests, dependent: :destroy
  has_many :user_interests, dependent: :destroy
end
