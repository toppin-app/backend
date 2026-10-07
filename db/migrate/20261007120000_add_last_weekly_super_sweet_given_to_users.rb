class AddLastWeeklySuperSweetGivenToUsers < ActiveRecord::Migration[6.0]
  def up
    add_column :users, :last_weekly_super_sweet_given, :datetime

    # The old timestamp records both grants and consumption. Conservatively
    # preserve it to avoid a second refill in the rollout week. A recent
    # consumption can postpone that first refill until the following Monday.
    execute <<~SQL
      UPDATE users
      SET last_weekly_super_sweet_given = last_superlike_given
      WHERE last_superlike_given IS NOT NULL
    SQL
  end

  def down
    remove_column :users, :last_weekly_super_sweet_given
  end
end
