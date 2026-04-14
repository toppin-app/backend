class BlackCoffeeImageUploader < ImageUploader
  def store_dir
    "uploads/black_coffee/venues/#{model.venue_id}/images/#{model.id}"
  end
end
