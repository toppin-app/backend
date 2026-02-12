class InterestCategory < ApplicationRecord
  has_many :interests, dependent: :destroy
end
