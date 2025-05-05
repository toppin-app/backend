class AddSocialLoginTokenToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :social_login_token, :string
  end
end
