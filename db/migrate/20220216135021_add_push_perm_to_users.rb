class AddPushPermToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :push_sound, :boolean, default: true
    add_column :users, :push_vibration, :boolean, default: true
  end
end
