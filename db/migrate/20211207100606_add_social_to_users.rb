class AddSocialToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :social, :string
  end
end
