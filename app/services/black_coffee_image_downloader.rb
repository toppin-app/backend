require 'net/http'
require 'uri'

class BlackCoffeeImageDownloader
  DEFAULT_MAX_DOWNLOAD_BYTES = 25.megabytes
  DEFAULT_OPEN_TIMEOUT = 4
  DEFAULT_READ_TIMEOUT = 8
  DEFAULT_MAX_REDIRECTS = 4
  DEFAULT_USER_AGENT = 'Toppin Black Coffee Image Downloader/1.0'.freeze

  DownloadResult = Struct.new(
    :ok?,
    :body,
    :content_type,
    :extension,
    :http_status,
    :error_type,
    :error_message,
    :final_url,
    keyword_init: true
  )

  def initialize(
    max_download_bytes: DEFAULT_MAX_DOWNLOAD_BYTES,
    open_timeout: DEFAULT_OPEN_TIMEOUT,
    read_timeout: DEFAULT_READ_TIMEOUT,
    max_redirects: DEFAULT_MAX_REDIRECTS,
    user_agent: DEFAULT_USER_AGENT
  )
    @max_download_bytes = max_download_bytes.to_i
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @max_redirects = max_redirects
    @user_agent = user_agent
  end

  def download(url)
    raw_url = url.to_s.strip
    return failure('missing_url', 'La URL esta vacia.') if raw_url.blank?
    if VenueImage.temporary_google_place_photo_url?(raw_url)
      return failure('temporary_google_photo_uri', 'URL temporal de Google Places; se evita comprobarla por red.')
    end

    uri = URI.parse(raw_url)
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

  attr_reader :max_download_bytes, :open_timeout, :read_timeout, :max_redirects, :user_agent

  def request_with_redirects(uri, redirects = 0)
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = user_agent

    result = nil
    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == 'https',
      open_timeout: open_timeout,
      read_timeout: read_timeout
    ) do |http|
      http.request(request) do |response|
        code = response.code.to_i

        if redirect?(code) && redirects < max_redirects
          location = response['location'].to_s
          return failure('redirect_without_location', 'La redireccion no indica destino.', code) if location.blank?

          return request_with_redirects(URI.join(uri, location), redirects + 1)
        end

        return failure('too_many_redirects', "La imagen redirige mas de #{max_redirects} veces.", code) if redirect?(code)
        return failure('http_error', "La imagen responde HTTP #{code}.", code) unless code == 200

        content_type = response['content-type'].to_s.split(';').first.to_s.downcase
        unless content_type.start_with?('image/')
          return failure(
            'not_image',
            "La URL responde 200, pero no parece una imagen (#{content_type.presence || 'sin content-type'}).",
            code
          )
        end

        body = +''
        response.read_body do |chunk|
          body << chunk
          if body.bytesize > max_download_bytes
            return failure('image_too_large', "La imagen supera #{max_download_bytes} bytes.", code)
          end
        end

        return failure('empty_image', 'La imagen responde 200 pero no tiene contenido.', code) if body.blank?

        result = DownloadResult.new(
          ok?: true,
          body: body,
          content_type: content_type,
          extension: extension_for(content_type, uri.path),
          http_status: code,
          final_url: uri.to_s
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
    DownloadResult.new(
      ok?: false,
      error_type: error_type,
      error_message: message,
      http_status: http_status
    )
  end
end
