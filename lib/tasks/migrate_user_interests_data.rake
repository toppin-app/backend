namespace :db do
  desc "Migrate data from user_interests to user_main_interests"
  task migrate_data: :environment do
    UserInterest.select("id, user_id, interest_id, interest_name").find_each do |user_interest|
      # Obtenemos el conteo de registros para el user_id actual
      count = UserMainInterest.where(user_id: user_interest.user_id).count

      # Si ya hemos migrado 4 registros para este user_id, pasamos al siguiente
      next if count >= 4

      # Creamos el nuevo registro en user_main_interests
      UserMainInterest.create(
        user_id: user_interest.user_id,
        interest_id: user_interest.interest_id,
        name: user_interest.interest_name
      )
    end
  end
end
