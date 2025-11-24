class RemoveEmailUniqueIndexAndAddPartialIndex < ActiveRecord::Migration[6.0]
  def up
    # Eliminar el índice único existente en email
    remove_index :users, :email if index_exists?(:users, :email)
    
    # En MySQL, crear un índice compuesto único en (email, deleted_account)
    # Esto permite emails duplicados si deleted_account es diferente
    add_index :users, [:email, :deleted_account], unique: true, name: 'index_users_on_email_and_deleted_account'
  end

  def down
    # Revertir: eliminar el índice compuesto
    remove_index :users, name: 'index_users_on_email_and_deleted_account' if index_exists?(:users, [:email, :deleted_account], name: 'index_users_on_email_and_deleted_account')
    
    # Restaurar el índice único original (solo si no hay duplicados)
    add_index :users, :email, unique: true
  end
end
