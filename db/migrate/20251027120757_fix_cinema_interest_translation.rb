class FixCinemaInterestTranslation < ActiveRecord::Migration[6.0]
  def up
    spanish = 'Cine (ir al cine)'
    english = 'cinema'
    
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

  def down
    english = 'cinema'
    spanish = 'Cine (ir al cine)'
    
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
