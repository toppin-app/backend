class FixMissingInterestTranslations < ActiveRecord::Migration[6.0]
  def up
    translations = {
      'Suspense (Thriller)' => 'thriller',
      'Gimnasio (Gym)' => 'gym',
      'Senderismo (Hiking)' => 'hiking',
      'Manualidades (DIY)' => 'diy_crafts',
      'Bailar (como hobby)' => 'dancing_hobby'
    }

    translations.each do |spanish, english|
      execute <<-SQL
        UPDATE interests SET name = '#{english}' WHERE name = '#{spanish}';
      SQL
      
      # También actualizar el campo interest_name en user_interests si existe
      if column_exists?(:user_interests, :interest_name)
        execute <<-SQL
          UPDATE user_interests SET interest_name = '#{english}' WHERE interest_name = '#{spanish}';
        SQL
      end
      
      # También actualizar el campo name en user_main_interests
      if column_exists?(:user_main_interests, :name)
        execute <<-SQL
          UPDATE user_main_interests SET name = '#{english}' WHERE name = '#{spanish}';
        SQL
      end
    end
  end

  def down
    # Reversión si necesitas volver al español
    translations = {
      'thriller' => 'Suspense (Thriller)',
      'gym' => 'Gimnasio (Gym)',
      'hiking' => 'Senderismo (Hiking)',
      'diy_crafts' => 'Manualidades (DIY)',
      'dancing_hobby' => 'Bailar (como hobby)'
    }

    translations.each do |english, spanish|
      execute <<-SQL
        UPDATE interests SET name = '#{spanish}' WHERE name = '#{english}';
      SQL
      
      if column_exists?(:user_interests, :interest_name)
        execute <<-SQL
          UPDATE user_interests SET interest_name = '#{spanish}' WHERE interest_name = '#{english}';
        SQL
      end
      
      if column_exists?(:user_main_interests, :name)
        execute <<-SQL
          UPDATE user_main_interests SET name = '#{spanish}' WHERE name = '#{english}';
        SQL
      end
    end
  end
end
