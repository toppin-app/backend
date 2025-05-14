class UserFilterPreference < ApplicationRecord
  belongs_to :user

  # Ya no uses enum, define una constante de opciones
  GENDERS = %w[female male gender_any couple]

  def gender_options
    GENDERS
  end
end