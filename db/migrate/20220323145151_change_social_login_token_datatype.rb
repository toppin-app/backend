class ChangeSocialLoginTokenDatatype < ActiveRecord::Migration[6.0]
  def change
	change_column :users, :social_login_token, :text
  end
end
