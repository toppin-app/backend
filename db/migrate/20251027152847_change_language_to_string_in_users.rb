class ChangeLanguageToStringInUsers < ActiveRecord::Migration[6.0]
  def up
    # Primero, añadir una columna temporal para almacenar los códigos de idioma
    add_column :users, :language_code, :string
    
    # Migrar los datos existentes: 0 → 'ES', 1 → 'EN'
    execute <<-SQL
      UPDATE users SET language_code = 'ES' WHERE language = 0;
    SQL
    
    execute <<-SQL
      UPDATE users SET language_code = 'EN' WHERE language = 1;
    SQL
    
    # Establecer valor por defecto para registros sin idioma
    execute <<-SQL
      UPDATE users SET language_code = 'ES' WHERE language_code IS NULL;
    SQL
    
    # Eliminar la columna antigua
    remove_column :users, :language
    
    # Renombrar la columna temporal a language
    rename_column :users, :language_code, :language
    
    # Añadir índice para mejorar rendimiento
    add_index :users, :language
  end

  def down
    # Reversión: convertir de strings a integers
    add_column :users, :language_int, :integer
    
    execute <<-SQL
      UPDATE users SET language_int = 0 WHERE language = 'ES';
    SQL
    
    execute <<-SQL
      UPDATE users SET language_int = 1 WHERE language = 'EN';
    SQL
    
    execute <<-SQL
      UPDATE users SET language_int = 0 WHERE language = 'IT' OR language = 'FR';
    SQL
    
    remove_index :users, :language if index_exists?(:users, :language)
    remove_column :users, :language
    rename_column :users, :language_int, :language
  end
end
