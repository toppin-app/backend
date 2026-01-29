class Interest < ApplicationRecord
  belongs_to :interest_category
  has_many :user_main_interests, dependent: :destroy
  has_many :user_interests, dependent: :destroy
end
