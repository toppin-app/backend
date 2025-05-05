class UserPersonalQuestion < ApplicationRecord
  belongs_to :user
  belongs_to :personal_question
end
