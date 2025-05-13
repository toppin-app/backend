class AppVersions < ApplicationRecord
  validates :android_last_version, presence: true
  validates :ios_last_version, presence: true
end