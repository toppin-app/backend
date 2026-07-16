require 'digest'

class BlackCoffeeImageInspector
  DEFAULT_MIN_WIDTH = 240
  DEFAULT_MIN_HEIGHT = 240
  DEFAULT_MIN_PIXELS = DEFAULT_MIN_WIDTH * DEFAULT_MIN_HEIGHT
  DEFAULT_MAX_PIXELS = 60_000_000

  JPEG_SIGNATURE = "\xFF\xD8\xFF".b.freeze
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze
  GIF_SIGNATURES = ["GIF87a".b.freeze, "GIF89a".b.freeze].freeze
  JPEG_START_OF_FRAME_MARKERS = %w[
    c0 c1 c2 c3 c5 c6 c7 c9 ca cb cd ce cf
  ].map { |value| value.to_i(16) }.freeze
  JPEG_MARKERS_WITHOUT_LENGTH = ((0xD0..0xD9).to_a + [0x01]).freeze

  FormatInfo = Struct.new(
    :format,
    :content_type,
    :extension,
    :width,
    :height,
    keyword_init: true
  )

  Result = Struct.new(
    :ok?,
    :format,
    :content_type,
    :extension,
    :width,
    :height,
    :pixels,
    :sha256,
    :error_type,
    :error_message,
    keyword_init: true
  )

  def initialize(
    min_width: DEFAULT_MIN_WIDTH,
    min_height: DEFAULT_MIN_HEIGHT,
    min_pixels: DEFAULT_MIN_PIXELS,
    max_pixels: DEFAULT_MAX_PIXELS
  )
    @min_width = [min_width.to_s.to_i, 0].max
    @min_height = [min_height.to_s.to_i, 0].max
    @min_pixels = [min_pixels.to_s.to_i, 0].max
    @max_pixels = [max_pixels.to_s.to_i, 1].max
  end

  def call(body, declared_content_type: nil)
    data = binary_string(body)
    sha256 = Digest::SHA256.hexdigest(data)
    return failure('empty_image', 'La imagen no contiene datos.', sha256: sha256) if data.empty?

    format_info = detect_format(data)
    unless format_info
      content_type = normalize_content_type(declared_content_type)
      return failure(
        'not_image',
        "El contenido no es un JPEG, PNG, GIF o WebP valido (Content-Type: #{content_type || 'sin content-type'}).",
        sha256: sha256
      )
    end

    width = format_info.width.to_i
    height = format_info.height.to_i
    unless width.positive? && height.positive?
      return failure(
        'invalid_image',
        "La cabecera #{format_info.format.upcase} no contiene dimensiones validas.",
        format_info: format_info,
        sha256: sha256
      )
    end

    pixels = width * height
    if pixels > max_pixels
      return failure(
        'image_dimensions_too_large',
        "La imagen declara #{width}x#{height} (#{pixels} pixeles), por encima del maximo de #{max_pixels}.",
        format_info: format_info,
        pixels: pixels,
        sha256: sha256
      )
    end
    if below_size_limits?(width, height, pixels)
      return failure(
        'image_too_small',
        too_small_message(width, height, pixels),
        format_info: format_info,
        pixels: pixels,
        sha256: sha256
      )
    end

    Result.new(
      ok?: true,
      format: format_info.format,
      content_type: format_info.content_type,
      extension: format_info.extension,
      width: width,
      height: height,
      pixels: pixels,
      sha256: sha256
    )
  end

  private

  attr_reader :min_width, :min_height, :min_pixels, :max_pixels

  def binary_string(value)
    value.to_s.dup.force_encoding(Encoding::BINARY)
  end

  def detect_format(data)
    jpeg_info(data) || png_info(data) || gif_info(data) || webp_info(data)
  end

  def jpeg_info(data)
    return nil unless data.start_with?(JPEG_SIGNATURE)

    dimensions = jpeg_dimensions(data)
    FormatInfo.new(
      format: 'jpeg',
      content_type: 'image/jpeg',
      extension: 'jpg',
      width: dimensions&.first,
      height: dimensions&.last
    )
  end

  def jpeg_dimensions(data)
    offset = 2

    while offset < data.bytesize
      marker_prefix = data.index("\xFF".b, offset)
      return nil unless marker_prefix

      offset = marker_prefix + 1
      offset += 1 while data.getbyte(offset) == 0xFF
      marker = data.getbyte(offset)
      return nil unless marker

      offset += 1
      next if marker == 0x00 || JPEG_MARKERS_WITHOUT_LENGTH.include?(marker)
      return nil if marker == 0xDA

      segment_length = uint16_be(data, offset)
      return nil unless segment_length && segment_length >= 2

      if JPEG_START_OF_FRAME_MARKERS.include?(marker)
        height = uint16_be(data, offset + 3)
        width = uint16_be(data, offset + 5)
        return [width, height] if width && height

        return nil
      end

      offset += segment_length
    end

    nil
  end

  def png_info(data)
    return nil unless data.start_with?(PNG_SIGNATURE)
    return nil unless uint32_be(data, 8) == 13 && data.byteslice(12, 4) == 'IHDR'.b

    FormatInfo.new(
      format: 'png',
      content_type: 'image/png',
      extension: 'png',
      width: uint32_be(data, 16),
      height: uint32_be(data, 20)
    )
  end

  def gif_info(data)
    return nil unless GIF_SIGNATURES.any? { |signature| data.start_with?(signature) }

    FormatInfo.new(
      format: 'gif',
      content_type: 'image/gif',
      extension: 'gif',
      width: uint16_le(data, 6),
      height: uint16_le(data, 8)
    )
  end

  def webp_info(data)
    return nil unless data.byteslice(0, 4) == 'RIFF'.b && data.byteslice(8, 4) == 'WEBP'.b

    dimensions = webp_dimensions(data)
    FormatInfo.new(
      format: 'webp',
      content_type: 'image/webp',
      extension: 'webp',
      width: dimensions&.first,
      height: dimensions&.last
    )
  end

  def webp_dimensions(data)
    offset = 12

    while offset + 8 <= data.bytesize
      chunk_type = data.byteslice(offset, 4)
      chunk_size = uint32_le(data, offset + 4)
      return nil unless chunk_type && chunk_size

      payload_offset = offset + 8
      return nil if payload_offset + chunk_size > data.bytesize

      dimensions = dimensions_for_webp_chunk(data, chunk_type, payload_offset, chunk_size)
      return dimensions if dimensions

      offset = payload_offset + chunk_size + (chunk_size.odd? ? 1 : 0)
    end

    nil
  end

  def dimensions_for_webp_chunk(data, chunk_type, payload_offset, chunk_size)
    case chunk_type
    when 'VP8X'.b
      return nil if chunk_size < 10

      [uint24_le(data, payload_offset + 4).to_i + 1, uint24_le(data, payload_offset + 7).to_i + 1]
    when 'VP8 '.b
      return nil if chunk_size < 10
      return nil unless data.byteslice(payload_offset + 3, 3) == "\x9D\x01\x2A".b

      [uint16_le(data, payload_offset + 6).to_i & 0x3FFF, uint16_le(data, payload_offset + 8).to_i & 0x3FFF]
    when 'VP8L'.b
      return nil if chunk_size < 5 || data.getbyte(payload_offset) != 0x2F

      bits = uint32_le(data, payload_offset + 1)
      return nil unless bits

      [(bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1]
    end
  end

  def below_size_limits?(width, height, pixels)
    width < min_width || height < min_height || pixels < min_pixels
  end

  def too_small_message(width, height, pixels)
    requirements = []
    requirements << "ancho minimo #{min_width}px" if min_width.positive?
    requirements << "alto minimo #{min_height}px" if min_height.positive?
    requirements << "area minima #{min_pixels} pixeles" if min_pixels.positive?

    "La imagen mide #{width}x#{height} (#{pixels} pixeles); se requiere #{requirements.join(', ')}."
  end

  def normalize_content_type(value)
    normalized = value.to_s.split(';', 2).first.to_s.strip.downcase
    normalized.empty? ? nil : normalized.gsub(/[^a-z0-9.+\/-]/, '')
  end

  def uint16_be(data, offset)
    unpack_integer(data, offset, 2, 'n')
  end

  def uint16_le(data, offset)
    unpack_integer(data, offset, 2, 'v')
  end

  def uint24_le(data, offset)
    bytes = data.byteslice(offset, 3)
    return nil unless bytes&.bytesize == 3

    bytes.getbyte(0) | (bytes.getbyte(1) << 8) | (bytes.getbyte(2) << 16)
  end

  def uint32_be(data, offset)
    unpack_integer(data, offset, 4, 'N')
  end

  def uint32_le(data, offset)
    unpack_integer(data, offset, 4, 'V')
  end

  def unpack_integer(data, offset, length, directive)
    bytes = data.byteslice(offset, length)
    return nil unless bytes&.bytesize == length

    bytes.unpack1(directive)
  end

  def failure(error_type, message, format_info: nil, pixels: nil, sha256: nil)
    Result.new(
      ok?: false,
      format: format_info&.format,
      content_type: format_info&.content_type,
      extension: format_info&.extension,
      width: format_info&.width,
      height: format_info&.height,
      pixels: pixels,
      sha256: sha256,
      error_type: error_type,
      error_message: message
    )
  end
end
