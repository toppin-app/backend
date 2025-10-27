class TranslateInfoItemValuesToEnglish < ActiveRecord::Migration[6.0]
  def up
    translations = {
      # Signos del zodiaco
      'Libra' => 'libra',
      'Aries' => 'aries',
      'Tauro' => 'taurus',
      'Géminis' => 'gemini',
      'Cáncer' => 'cancer',
      'Leo' => 'leo',
      'Virgo' => 'virgo',
      'Escorpio' => 'scorpio',
      'Sagitario' => 'sagittarius',
      'Capricornio' => 'capricorn',
      'Acuario' => 'aquarius',
      'Piscis' => 'pisces',
      
      # Orientación sexual
      'Pansexual' => 'pansexual',
      'Queer' => 'queer',
      'Tengo dudas' => 'questioning',
      'Arromantico' => 'aromantic',
      'Omnisexual' => 'omnisexual',
      'Heterosexual' => 'heterosexual',
      'Gay' => 'gay',
      'Lesbiana' => 'lesbian',
      'Bisexual' => 'bisexual',
      'Asexual' => 'asexual',
      'Demisexual' => 'demisexual',
      
      # Tabaco
      'Fumo con amigos' => 'smoke_with_friends',
      'Fumo cuando salgo de fiesta' => 'smoke_when_partying',
      'No fumo' => 'non_smoker',
      'Fumo' => 'smoker',
      'Intentando dejarlo' => 'trying_to_quit',
      
      # Alcohol
      'Cada día' => 'every_day',
      'Normalmente' => 'usually',
      'Nunca' => 'never',
      'De vez en cuando' => 'occasionally',
      'No bebo alcohol' => 'non_drinker',
      'Los fines de semana' => 'on_weekends',
      'Todos los días' => 'daily',
      'En fechas señaladas' => 'on_special_occasions',
      
      # Religión
      'Cristianismo' => 'christianity',
      'Islam' => 'islam',
      'Hinduismo' => 'hinduism',
      'Budismo' => 'buddhism',
      'Judaísmo' => 'judaism',
      'Ateísmo' => 'atheism',
      'Agnosticismo' => 'agnosticism',
      'Sijismo' => 'sikhism',
      'Espiritual pero no religioso' => 'spiritual_but_not_religious',
      'Otra religión' => 'other_religion',
      
      # Estatura
      '1,35 m a 1,40 m' => '135_to_140_cm',
      '1,40 m a 1,45 m' => '140_to_145_cm',
      '1,45 m a 1,50 m' => '145_to_150_cm',
      '1,50 m a 1,55 m' => '150_to_155_cm',
      '1,55 m a 1,60 m' => '155_to_160_cm',
      '1,60 m a 1,65 m' => '160_to_165_cm',
      '1,65 m a 1,70 m' => '165_to_170_cm',
      '1,70 m a 1,75 m' => '170_to_175_cm',
      '1,75 m a 1,80 m' => '175_to_180_cm',
      '1,80 m a 1,85 m' => '180_to_185_cm',
      '1,85 m a 1,90 m' => '185_to_190_cm',
      '1,90 m a 1,95 m' => '190_to_195_cm',
      '1,95 m a 2,00 m' => '195_to_200_cm',
      '2,00 m a 2,05 m' => '200_to_205_cm',
      '2,05 m a 2,10 m' => '205_to_210_cm',
      '2,10 m a 2,15 m' => '210_to_215_cm',
      '2,15 m a 2,20 m' => '215_to_220_cm',
      
      # Mascotas
      'Tengo perro(s)' => 'have_dog',
      'Tengo gato(s)' => 'have_cat',
      'Tengo perro(s) y gato(s)' => 'have_dog_and_cat',
      'Tengo tortuga(s)' => 'have_turtle',
      'Tengo pez/peces' => 'have_fish',
      'Tengo reptil(es)' => 'have_reptile',
      'Tengo anfibio(s)' => 'have_amphibian',
      'Tengo hámster(s)' => 'have_hamster',
      'Tengo conejo(s)' => 'have_rabbit',
      'Tengo otro tipo de mascota' => 'have_other_pet',
      'No tengo mascotas' => 'no_pets',
      'Me gustan las mascotas, pero no tengo' => 'like_pets_but_dont_have',
      'No me gustan las mascotas' => 'dont_like_pets',
      'Prefiero no decirlo' => 'prefer_not_to_say',
      
      # Busco
      'Una relación seria' => 'serious_relationship',
      'Algo informal' => 'casual_dating',
      'Amistad' => 'friendship',
      'Conocer gente nueva' => 'meeting_new_people',
      'Una cita ocasional' => 'occasional_date',
      'Relación abierta' => 'open_relationship',
      'No estoy seguro/a' => 'not_sure',
      'Solo pasar el rato' => 'just_hanging_out',
      'Relación a distancia' => 'long_distance_relationship',
      
      # Formación
      'Grado Universitario' => 'university_degree',
      'Grado Superior' => 'higher_vocational_training',
      'Estudios basicos' => 'basic_education',
      'Grado Medio' => 'intermediate_vocational_training',
      
      # Hijos
      'No tengo hijo/a' => 'no_children',
      'Tengo 1 hijo/a' => 'have_1_child',
      'Tengo 2 hijos/as' => 'have_2_children',
      'Tengo 3 hijos/as' => 'have_3_children',
      'Tengo mas de 4 hijos/as' => 'have_more_than_4_children',
      
      # Trabajo
      'Estoy trabajando actualmente' => 'currently_working',
      'No tengo trabajo' => 'unemployed',
      
      # Política
      'Apolítco' => 'apolitical',
      'De derechas' => 'right_wing',
      'De izquierdas' => 'left_wing',
      'De centro' => 'center'
    }

    translations.each do |spanish, english|
      # Escapar comillas simples para SQL
      spanish_escaped = spanish.gsub("'", "''")
      english_escaped = english.gsub("'", "''")
      
      execute <<-SQL
        UPDATE info_item_values SET value = '#{english_escaped}' WHERE value = '#{spanish_escaped}';
      SQL
      
      # También actualizar el campo item_name en user_info_item_values si existe
      if column_exists?(:user_info_item_values, :item_name)
        execute <<-SQL
          UPDATE user_info_item_values SET item_name = '#{english_escaped}' WHERE item_name = '#{spanish_escaped}';
        SQL
      end
    end
  end

  def down
    # No implementamos reversión porque sería muy complejo y no necesario
    # Si necesitas volver atrás, mejor restaurar desde backup
    raise ActiveRecord::IrreversibleMigration
  end
end
