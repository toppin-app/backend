require 'ipaddr'
require 'net/http'
require 'resolv'
require 'uri'

class BlackCoffeeImageDownloader
  DEFAULT_MAX_DOWNLOAD_BYTES = 25.megabytes
  DEFAULT_OPEN_TIMEOUT = 4
  DEFAULT_READ_TIMEOUT = 8
  DEFAULT_MAX_REDIRECTS = 4
  DEFAULT_USER_AGENT = 'Toppin Black Coffee Image Downloader/1.0'.freeze
  DEFAULT_ACCEPT = 'image/webp,image/png,image/jpeg,image/gif;q=0.9,*/*;q=0.1'.freeze
  # Technical validity is the shared default. Product-specific quality floors
  # (concert covers use 240x240) are supplied by the caller so other importers
  # keep their existing behaviour.
  DEFAULT_MIN_WIDTH = 1
  DEFAULT_MIN_HEIGHT = 1
  DEFAULT_MIN_PIXELS = 1
  DEFAULT_MAX_PIXELS = BlackCoffeeImageInspector::DEFAULT_MAX_PIXELS
  BLOCKED_NETWORKS = %w[
    0.0.0.0/8
    10.0.0.0/8
    100.64.0.0/10
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.0.0.0/24
    192.0.2.0/24
    192.168.0.0/16
    198.18.0.0/15
    198.51.100.0/24
    203.0.113.0/24
    224.0.0.0/4
    240.0.0.0/4
    ::/128
    ::1/128
    2001:db8::/32
    fc00::/7
    fe80::/10
    ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  DownloadResult = Struct.new(
    :ok?,
    :body,
    :content_type,
    :extension,
    :http_status,
    :error_type,
    :error_message,
    :final_url,
    :width,
    :height,
    :pixels,
    :byte_size,
    :sha256,
    :declared_content_type,
    keyword_init: true
  )

  def initialize(
    max_download_bytes: DEFAULT_MAX_DOWNLOAD_BYTES,
    open_timeout: DEFAULT_OPEN_TIMEOUT,
    read_timeout: DEFAULT_READ_TIMEOUT,
    max_redirects: DEFAULT_MAX_REDIRECTS,
    user_agent: DEFAULT_USER_AGENT,
    min_width: DEFAULT_MIN_WIDTH,
    min_height: DEFAULT_MIN_HEIGHT,
    min_pixels: DEFAULT_MIN_PIXELS,
    max_pixels: DEFAULT_MAX_PIXELS,
    validate_visual_content: false,
    inspector: nil,
    address_resolver: ->(host) { Resolv.getaddresses(host) },
    http_factory: nil
  )
    @max_download_bytes = max_download_bytes.to_i
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @max_redirects = max_redirects
    @user_agent = user_agent
    @inspector = inspector || BlackCoffeeImageInspector.new(
      min_width: min_width,
      min_height: min_height,
      min_pixels: min_pixels,
      max_pixels: max_pixels,
      validate_visual_content: validate_visual_content
    )
    @address_resolver = address_resolver
    @http_factory = http_factory || method(:build_http)
  end

  def download(url)
    raw_url = url.to_s.strip
    return failure('missing_url', 'La URL esta vacia.') if raw_url.blank?
    if VenueImage.temporary_google_place_photo_url?(raw_url)
      return failure('temporary_google_photo_uri', 'URL temporal de Google Places; se evita comprobarla por red.')
    end

    uri = URI.parse(raw_url)
    return failure('invalid_url', 'La URL no usa http o https o no incluye host.') unless uri.is_a?(URI::HTTP) && uri.host.present?

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

  attr_reader :max_download_bytes, :open_timeout, :read_timeout, :max_redirects, :user_agent, :inspector, :address_resolver, :http_factory

  def request_with_redirects(uri, redirects = 0)
    public_address = public_address_for(uri)
    return public_address if public_address.is_a?(DownloadResult)

    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = user_agent
    request['Accept'] = DEFAULT_ACCEPT

    result = nil
    http_factory.call(uri, public_address).start do |http|
      http.request(request) do |response|
        code = response.code.to_i

        if redirect?(code) && redirects < max_redirects
          location = response['location'].to_s
          return failure('redirect_without_location', 'La redireccion no indica destino.', code) if location.blank?

          return request_with_redirects(URI.join(uri, location), redirects + 1)
        end

        return failure('too_many_redirects', "La imagen redirige mas de #{max_redirects} veces.", code) if redirect?(code)
        return failure('http_error', "La imagen responde HTTP #{code}.", code) unless code == 200

        declared_content_type = normalized_content_type(response['content-type'])
        body = String.new(encoding: Encoding::BINARY)
        response.read_body do |chunk|
          chunk = chunk.to_s.b
          observed_size = body.bytesize + chunk.bytesize
          if observed_size > max_download_bytes
            return failure(
              'image_too_large',
              "La imagen supera #{max_download_bytes} bytes.",
              code,
              final_url: uri.to_s,
              byte_size: observed_size,
              declared_content_type: declared_content_type
            )
          end
          body << chunk
        end

        if body.empty?
          return failure(
            'empty_image',
            'La imagen responde 200 pero no tiene contenido.',
            code,
            final_url: uri.to_s,
            byte_size: 0,
            declared_content_type: declared_content_type
          )
        end

        inspection = inspector.call(
          body,
          declared_content_type: declared_content_type
        )
        unless inspection.ok?
          return failure(
            inspection.error_type,
            inspection.error_message,
            code,
            content_type: inspection.content_type,
            extension: inspection.extension,
            final_url: uri.to_s,
            width: inspection.width,
            height: inspection.height,
            pixels: inspection.pixels,
            byte_size: body.bytesize,
            sha256: inspection.sha256,
            declared_content_type: declared_content_type
          )
        end

        result = DownloadResult.new(
          ok?: true,
          body: body,
          content_type: inspection.content_type,
          extension: inspection.extension,
          http_status: code,
          final_url: uri.to_s,
          width: inspection.width,
          height: inspection.height,
          pixels: inspection.pixels,
          byte_size: body.bytesize,
          sha256: inspection.sha256,
          declared_content_type: declared_content_type
        )
      end
    end
    result || failure('empty_response', 'No se pudo leer la respuesta de la imagen.')
  end

  def redirect?(code)
    code.between?(300, 399)
  end

  def public_address_for(uri)
    return failure('invalid_url', 'La URL incluye credenciales y no es valida para descargar imagenes.') if uri.userinfo.present?

    host = uri.host.to_s.downcase
    return failure('blocked_destination', 'La URL apunta a un host local o interno.') if local_hostname?(host)

    addresses = Array(address_resolver.call(host)).filter_map do |address|
      parsed = IPAddr.new(address)
      parsed.ipv4_mapped? ? parsed.native : parsed
    rescue IPAddr::InvalidAddressError
      nil
    end
    return failure('network_error', 'No se pudo resolver el host de la imagen.') if addresses.empty?
    return failure('blocked_destination', 'La URL de imagen resuelve a una red privada o reservada.') if addresses.any? { |address| blocked_address?(address) }

    addresses.first.to_s
  rescue Resolv::ResolvError, SocketError, SystemCallError => e
    failure('network_error', e.message)
  end

  def build_http(uri, public_address)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = public_address
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout
    http
  end

  def local_hostname?(host)
    host == 'localhost' || host.end_with?('.localhost', '.local', '.internal')
  end

  def blocked_address?(address)
    BLOCKED_NETWORKS.any? { |network| network.include?(address) }
  end

  def normalized_content_type(value)
    normalized = value.to_s.split(';', 2).first.to_s.strip.downcase
    normalized.presence
  end

  def failure(
    error_type,
    message,
    http_status = nil,
    content_type: nil,
    extension: nil,
    final_url: nil,
    width: nil,
    height: nil,
    pixels: nil,
    byte_size: nil,
    sha256: nil,
    declared_content_type: nil
  )
    DownloadResult.new(
      ok?: false,
      content_type: content_type,
      extension: extension,
      error_type: error_type,
      error_message: message,
      http_status: http_status,
      final_url: final_url,
      width: width,
      height: height,
      pixels: pixels,
      byte_size: byte_size,
      sha256: sha256,
      declared_content_type: declared_content_type
    )
  end
end
