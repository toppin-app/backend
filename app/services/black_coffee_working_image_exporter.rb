require 'json'
require 'net/http'
require 'stringio'
require 'uri'
require 'zip'

class BlackCoffeeWorkingImageExporter
  DEFAULT_LIMIT = 100
  MAX_LIMIT = 1_000
  MAX_DOWNLOAD_BYTES = 25.megabytes
  MAX_SCAN_MULTIPLIER = 8
  USER_AGENT = 'Toppin Black Coffee Image Exporter/1.0'.freeze

  DownloadResult = Struct.new(:ok?, :body, :content_type, :extension, :http_status, :error_type, :error_message, keyword_init: true)
  ExportResult = Struct.new(:zip_data, :filename, :manifest, keyword_init: true)

  def initialize(limit:, offset: 0, base_url:, downloader: ImageDownloader.new, image_scope: nil)
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

  class ImageDownloader
    MAX_REDIRECTS = 4

    def download(url)
      uri = URI.parse(url)
      return failure('invalid_url', 'La URL no usa http o https.') unless uri.is_a?(URI::HTTP)

      request_with_redirects(uri)
    rescue URI::InvalidURIError => e
      failure('invalid_url', e.message)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      failure('timeout', e.message)
    rescue SocketError, SystemCallError => e
      failure('network_error', e.message)
    rescue StandardError => e
      failure('unknown_error', e.message)
    end

    private

    def request_with_redirects(uri, redirects = 0)
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = USER_AGENT

      result = nil
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 4, read_timeout: 8) do |http|
        http.request(request) do |response|
          code = response.code.to_i

          if redirect?(code) && redirects < MAX_REDIRECTS
            location = response['location'].to_s
            return failure('redirect_without_location', 'La redireccion no indica destino.', code) if location.blank?

            return request_with_redirects(URI.join(uri, location), redirects + 1)
          end

          return failure('http_error', "La imagen responde HTTP #{code}.", code) unless code == 200

          content_type = response['content-type'].to_s.split(';').first.to_s.downcase
          return failure('not_image', "La URL responde 200, pero no parece una imagen (#{content_type.presence || 'sin content-type'}).", code) unless content_type.start_with?('image/')

          body = +''
          response.read_body do |chunk|
            body << chunk
            return failure('image_too_large', "La imagen supera #{MAX_DOWNLOAD_BYTES} bytes.", code) if body.bytesize > MAX_DOWNLOAD_BYTES
          end

          return failure('empty_image', 'La imagen responde 200 pero no tiene contenido.', code) if body.blank?

          result = DownloadResult.new(
            ok?: true,
            body: body,
            content_type: content_type,
            extension: extension_for(content_type, uri.path),
            http_status: code
          )
        end
      end
      result || failure('empty_response', 'No se pudo leer la respuesta de la imagen.')
    end

    def redirect?(code)
      code.between?(300, 399)
    end

    def extension_for(content_type, path)
      return 'jpg' if content_type == 'image/jpeg'
      return 'png' if content_type == 'image/png'
      return 'webp' if content_type == 'image/webp'
      return 'gif' if content_type == 'image/gif'

      extension = File.extname(path.to_s).delete('.').downcase
      extension.presence || 'jpg'
    end

    def failure(error_type, message, http_status = nil)
      DownloadResult.new(ok?: false, error_type: error_type, error_message: message, http_status: http_status)
    end
  end
end
