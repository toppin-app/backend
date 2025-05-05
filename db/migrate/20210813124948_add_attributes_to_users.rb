class AddAttributesToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :phone_validated, :bool, :default => false
    add_column :users, :verified, :bool, :default => false
    add_column :users, :verification_file, :string
    add_column :users, :push_token, :string
    add_column :users, :device_id, :string
    add_column :users, :device_platform, :integer
    add_column :users, :description, :text
    add_column :users, :gender, :integer
    add_column :users, :high_visibility, :bool, :default => false
    add_column :users, :high_visibility_expire, :datetime
    add_column :users, :hidden_by_user, :bool, :default => false
    add_column :users, :is_connected, :bool, :default => true
    add_column :users, :last_connection, :datetime
    add_column :users, :last_match, :datetime
    add_column :users, :is_new, :bool, :default => true
    add_column :users, :activity_level, :integer
    add_column :users, :birthday, :date
    add_column :users, :born_in, :string
    add_column :users, :living_in, :string
    add_column :users, :locality, :string
    add_column :users, :country, :string
    add_column :users, :lat, :string
    add_column :users, :lng, :string
    add_column :users, :occupation, :string
    add_column :users, :studies, :string
  end
end
