class TranslateInfoItemCategoriesToEnglish < ActiveRecord::Migration[6.0]
  def up
    translations = {
      'Estatura' => 'height',
      'Trabajo' => 'job',
      'Signo del zodiaco' => 'zodiac_sign',
      'Mascotas' => 'pets',
      'Orientación sexual' => 'sexual_orientation',
      'Busco' => 'looking_for',
      'Religión' => 'religion',
      'Política' => 'politics',
      'Hijos' => 'children',
      'Tabaco' => 'smoking',
      'Formación' => 'education',
      'Deporte' => 'sports',
      'Alcohol' => 'drinking'
    }

    translations.each do |spanish, english|
      execute <<-SQL
        UPDATE info_item_categories SET name = '#{english}' WHERE name = '#{spanish}';
      SQL
      
      # También actualizar el campo category_name en user_info_item_values si existe
      if column_exists?(:user_info_item_values, :category_name)
        execute <<-SQL
          UPDATE user_info_item_values SET category_name = '#{english}' WHERE category_name = '#{spanish}';
        SQL
      end
    end
  end

  def down
    # Reversión si necesitas volver al español
    translations = {
      'height' => 'Estatura',
      'job' => 'Trabajo',
      'zodiac_sign' => 'Signo del zodiaco',
      'pets' => 'Mascotas',
      'sexual_orientation' => 'Orientación sexual',
      'looking_for' => 'Busco',
      'religion' => 'Religión',
      'politics' => 'Política',
      'children' => 'Hijos',
      'smoking' => 'Tabaco',
      'education' => 'Formación',
      'sports' => 'Deporte',
      'drinking' => 'Alcohol'
    }

    translations.each do |english, spanish|
      execute <<-SQL
        UPDATE info_item_categories SET name = '#{spanish}' WHERE name = '#{english}';
      SQL
      
      if column_exists?(:user_info_item_values, :category_name)
        execute <<-SQL
          UPDATE user_info_item_values SET category_name = '#{spanish}' WHERE category_name = '#{english}';
        SQL
      end
    end
  end
end
