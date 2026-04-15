require 'open-uri'
require 'tempfile'

class StoreBlackCoffeeImagesAsBinary < ActiveRecord::Migration[6.0]
  class MigratingVenueImage < ActiveRecord::Base
    self.table_name = 'venue_images'
    mount_uploader :image, BlackCoffeeImageUploader
  end

  CONTENT_TYPE_EXTENSIONS = {
    'image/jpeg' => '.jpg',
    'image/png' => '.png',
    'image/gif' => '.gif',
    'image/webp' => '.webp'
  }.freeze

  def up
    add_column :venue_images, :image, :string unless column_exists?(:venue_images, :image)
    MigratingVenueImage.reset_column_information

    # Si la tabla está vacía o no existe la columna url, solo agregamos la columna
    unless column_exists?(:venue_images, :url) && MigratingVenueImage.exists?
      say 'Skipping image migration - no legacy URLs found'
      return
    end

    say_with_time 'Migrating Black Coffee images from external URLs to binary storage' do
      migrated_count = 0
      failed_count = 0
      
      MigratingVenueImage.find_each do |record|
        legacy_url = record.read_attribute(:url).to_s.strip
        next if legacy_url.empty?
        next if record.read_attribute(:image).present?

        begin
          download_and_store_image!(record, legacy_url)
          migrated_count += 1
        rescue StandardError => e
          failed_count += 1
          say "Warning: Failed to migrate image for venue_image #{record.id}: #{e.message}", true
        end
      end
      
      say "Migrated #{migrated_count} images, #{failed_count} failed"
    end

    if column_exists?(:venue_images, :url)
      remove_column :venue_images, :url, :string
    end
  end

  def down
    add_column :venue_images, :url, :string unless column_exists?(:venue_images, :url)
    MigratingVenueImage.reset_column_information

    say_with_time 'Restoring venue image URLs from stored binaries' do
      MigratingVenueImage.where.not(image: [nil, '']).find_each do |record|
        record.update_columns(url: record.image.url) if record.image.present?
      end
    end

    remove_column :venue_images, :image, :string if column_exists?(:venue_images, :image)
  end

  private

  def download_and_store_image!(record, url)
    attempts = 0
    max_attempts = 2

    begin
      attempts += 1
      image_io = URI.open(url, 'User-Agent' => 'Toppin BlackCoffee Migrator', open_timeout: 5, read_timeout: 10)
      content_type =
        if image_io.respond_to?(:content_type)
          image_io.content_type.to_s.split(';').first.to_s.strip
        else
          ''
        end
      extension = extension_for(content_type, image_io.respond_to?(:base_uri) ? image_io.base_uri&.path.to_s : url)
      tempfile = Tempfile.new(["black-coffee-venue-image-#{record.id}", extension])
      tempfile.binmode
      IO.copy_stream(image_io, tempfile)
      tempfile.rewind

      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: tempfile,
        filename: "black-coffee-venue-image-#{record.id}#{extension}",
        type: normalized_content_type(content_type)
      )

      record.image = uploaded_file
      record.save!
    rescue StandardError => e
      retry if attempts < max_attempts
      raise e
    ensure
      image_io.close if defined?(image_io) && image_io.respond_to?(:close)
      if defined?(tempfile) && tempfile
        tempfile.close
        tempfile.unlink
      end
    end
  end

  def extension_for(content_type, source_path)
    return CONTENT_TYPE_EXTENSIONS[content_type] if CONTENT_TYPE_EXTENSIONS.key?(content_type)

    source_extension = File.extname(source_path.to_s).downcase
    return source_extension if source_extension.present?

    '.jpg'
  end

  def normalized_content_type(content_type)
    return content_type if CONTENT_TYPE_EXTENSIONS.key?(content_type)

    'image/jpeg'
  end
end
