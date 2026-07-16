# ImageUploader already uses local file storage explicitly. Keep the effective
# backend unchanged here: BlackCoffeeImageUploader is shared by concerts,
# festivals and the rest of Black Coffee, so switching it globally would require
# a separate migration/backfill plan for every existing asset.
CarrierWave.configure do |config|
  config.storage = :file
end
