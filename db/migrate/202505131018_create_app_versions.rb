class CreateAppVersions < ActiveRecord::Migration[6.0]
  def change
    create_table :app_versions do |t|
      t.string :android_last_version
      t.string :android_last_version_required
      t.string :ios_last_version
      t.string :ios_last_version_required
      t.string :android_store_link
      t.string :ios_store_link
    end
  end
end