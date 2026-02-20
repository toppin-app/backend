class RemoveDefaultFromBannerUsersViewedAt < ActiveRecord::Migration[6.0]
  def up
    # Eliminar el default de viewed_at para poder controlar cuándo se marca como visto
    change_column_default :banner_users, :viewed_at, from: -> { "CURRENT_TIMESTAMP" }, to: nil
    change_column_null :banner_users, :viewed_at, true
    
    # Eliminar el default de viewed también
    change_column_default :banner_users, :viewed, from: true, to: false
  end

  def down
    change_column_default :banner_users, :viewed_at, from: nil, to: -> { "CURRENT_TIMESTAMP" }
    change_column_null :banner_users, :viewed_at, false
    change_column_default :banner_users, :viewed, from: false, to: true
  end
end
