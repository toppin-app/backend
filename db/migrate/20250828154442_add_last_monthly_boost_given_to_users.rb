class AddLastMonthlyBoostGivenToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :last_monthly_boost_given, :datetime
  end
end