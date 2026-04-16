class EnableHybridBlackCoffeeImages < ActiveRecord::Migration[6.0]
  def up
    add_column :venue_images, :image, :string unless column_exists?(:venue_images, :image)
    add_column :venue_images, :url, :string unless column_exists?(:venue_images, :url)

    change_column_null :venue_images, :url, true if column_exists?(:venue_images, :url)
  end

  def down
    if column_exists?(:venue_images, :image)
      images_without_url = execute(<<~SQL.squish).first['count'].to_i
        SELECT COUNT(*) AS count
        FROM venue_images
        WHERE image IS NOT NULL
          AND image != ''
          AND (url IS NULL OR url = '')
      SQL

      if images_without_url.positive?
        raise ActiveRecord::IrreversibleMigration,
              'Cannot remove venue_images.image while binary-only images still exist'
      end

      remove_column :venue_images, :image, :string
    end

    if column_exists?(:venue_images, :url)
      change_column_null :venue_images, :url, false
    end
  end
end
