class AddVerificationImageToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :verification_image, :string
  end
end
