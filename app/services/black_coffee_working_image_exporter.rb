require 'json'
require 'stringio'
require 'zip'

class BlackCoffeeWorkingImageExporter
  DEFAULT_LIMIT = 100
  MAX_LIMIT = 1_000
  MAX_DOWNLOAD_BYTES = 25.megabytes
  MAX_SCAN_MULTIPLIER = 8
  USER_AGENT = 'Toppin Black Coffee Image Exporter/1.0'.freeze

  DownloadResult = BlackCoffeeImageDownloader::DownloadResult
  ExportResult = Struct.new(:zip_data, :filename, :manifest, keyword_init: true)

  def initialize(limit:, offset: 0, base_url:, downloader: default_downloader, image_scope: nil)
    @limit = [[limit.to_i, 1].max, MAX_LIMIT].min
    @offset = [offset.to_i, 0].max
    @base_url = base_url.to_s
    @downloader = downloader
    @image_scope = image_scope
  end

  def export
    manifest = build_manifest
    buffer = Zip::OutputStream.write_buffer do |zip|
      each_candidate_image do |image|
        break if manifest[:included_count] >= limit

        process_image(zip, manifest, image)
      end

      zip.put_next_entry('manifest.json')
      zip.write(JSON.pretty_generate(manifest))
    end

    buffer.rewind
    ExportResult.new(
      zip_data: buffer.string,
      filename: "black-coffee-working-images-#{Time.current.strftime('%Y%m%d-%H%M%S')}.zip",
      manifest: manifest
    )
  end

  private

  attr_reader :limit, :offset, :base_url, :downloader, :image_scope

  def build_manifest
    {
      generated_at: Time.current.iso8601,
      requested_limit: limit,
      offset: offset,
      max_candidates_scanned: max_candidates_to_scan,
      included_count: 0,
      skipped_count: 0,
      total_downloaded_bytes: 0,
      images: [],
      skipped: []
    }
  end

  def each_candidate_image(&block)
    records = image_scope || default_image_scope

    if records.respond_to?(:offset) && records.respond_to?(:limit)
      records.offset(offset).limit(max_candidates_to_scan).to_a.each(&block)
    else
      Array(records).drop(offset).first(max_candidates_to_scan).each(&block)
    end
  end

  def default_image_scope
    VenueImage
      .includes(:venue)
      .references(:venue)
      .joins(:venue)
      .order('venues.id ASC, venue_images.position ASC, venue_images.id ASC')
  end

  def max_candidates_to_scan
    [limit * MAX_SCAN_MULTIPLIER, limit].max
  end

  def process_image(zip, manifest, image)
    if image.temporary_google_place_photo_url?
      add_skip(manifest, image, nil, 'temporary_google_photo_uri', 'URL temporal de Google Places; se evita comprobarla por red.')
      return
    end

    public_url = image.public_url(base_url: base_url)
    if public_url.blank?
      add_skip(manifest, image, nil, 'missing_public_url', 'La imagen no tiene URL publica utilizable.')
      return
    end

    result = download_image(image, public_url)
    unless result.ok?
      add_skip(manifest, image, public_url, result.error_type, result.error_message, result.http_status)
      return
    end

    entry_name = zip_entry_name(image, result, manifest[:included_count] + 1)
    zip.put_next_entry(entry_name)
    zip.write(result.body)

    manifest[:included_count] += 1
    manifest[:total_downloaded_bytes] += result.body.bytesize
    manifest[:images] << image_manifest(image, public_url, entry_name, result)
  end

  def download_image(image, public_url)
    return download_uploaded_image(image) if image.uploaded_image?

    downloader.download(public_url)
  end

  def download_uploaded_image(image)
    path = image.image.path.to_s
    return failure('missing_file', 'El archivo subido no existe en disco.') if path.blank? || !File.file?(path)

    body = File.binread(path)
    return failure('file_too_large', "La imagen supera #{MAX_DOWNLOAD_BYTES} bytes.") if body.bytesize > MAX_DOWNLOAD_BYTES

    DownloadResult.new(
      ok?: true,
      body: body,
      content_type: content_type_from_extension(File.extname(path)),
      extension: extension_from_path(path),
      http_status: nil
    )
  rescue SystemCallError => e
    failure('file_error', e.message)
  end

  def add_skip(manifest, image, url, error_type, error_message, http_status = nil)
    manifest[:skipped_count] += 1
    manifest[:skipped] << {
      venue_id: image.venue_id,
      venue_name: image.venue&.name,
      venue_image_id: image.id,
      url: url,
      error_type: error_type,
      http_status: http_status,
      error_message: error_message
    }
  end

  def image_manifest(image, public_url, entry_name, result)
    {
      venue_id: image.venue_id,
      venue_name: image.venue&.name,
      venue_image_id: image.id,
      position: image.position,
      file: entry_name,
      source_url: public_url,
      content_type: result.content_type,
      http_status: result.http_status,
      bytes: result.body.bytesize
    }
  end

  def zip_entry_name(image, result, number)
    venue_slug = safe_filename(image.venue&.name.presence || image.venue_id || 'venue')
    extension = result.extension.presence || 'jpg'
    format('%03d_%s_%s.%s', number, image.venue_id || 'venue', venue_slug, extension)
  end

  def safe_filename(value)
    value.to_s.parameterize.presence || 'black-coffee-image'
  end

  def failure(error_type, message, http_status = nil)
    DownloadResult.new(ok?: false, error_type: error_type, error_message: message, http_status: http_status)
  end

  def extension_from_path(path)
    File.extname(path).delete('.').downcase.presence || 'jpg'
  end

  def content_type_from_extension(extension)
    normalized = extension.to_s.delete('.').downcase
    return 'image/jpeg' if %w[jpg jpeg].include?(normalized)
    return 'image/png' if normalized == 'png'
    return 'image/webp' if normalized == 'webp'
    return 'image/gif' if normalized == 'gif'

    'application/octet-stream'
  end

  def default_downloader
    BlackCoffeeImageDownloader.new(
      max_download_bytes: MAX_DOWNLOAD_BYTES,
      user_agent: USER_AGENT
    )
  end
end
