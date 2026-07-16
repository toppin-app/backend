require 'digest'
require 'mini_magick'
require 'zlib'

class BlackCoffeeImageInspector
  DEFAULT_MIN_WIDTH = 240
  DEFAULT_MIN_HEIGHT = 240
  DEFAULT_MIN_PIXELS = DEFAULT_MIN_WIDTH * DEFAULT_MIN_HEIGHT
  DEFAULT_MAX_PIXELS = 60_000_000
  DEFAULT_MIN_OPAQUE_FRACTION = 0.08
  DEFAULT_MIN_VISUAL_VARIATION = 0.008
  VISUAL_SAMPLE_EDGE = 64
  VISUAL_INSPECTION_TIMEOUT_SECONDS = 6
  MAX_INLINE_PNG_DECODE_BYTES = 2.megabytes

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
    :opaque_fraction,
    :visual_variation,
    :color_count,
    :error_type,
    :error_message,
    keyword_init: true
  )

  VisualMetrics = Struct.new(
    :ok?,
    :width,
    :height,
    :opaque_fraction,
    :visual_variation,
    :color_count,
    :error_type,
    :error_message,
    keyword_init: true
  )

  def initialize(
    min_width: DEFAULT_MIN_WIDTH,
    min_height: DEFAULT_MIN_HEIGHT,
    min_pixels: DEFAULT_MIN_PIXELS,
    max_pixels: DEFAULT_MAX_PIXELS,
    min_opaque_fraction: DEFAULT_MIN_OPAQUE_FRACTION,
    min_visual_variation: DEFAULT_MIN_VISUAL_VARIATION,
    validate_visual_content: false,
    visual_analyzer: nil
  )
    @min_width = [min_width.to_s.to_i, 0].max
    @min_height = [min_height.to_s.to_i, 0].max
    @min_pixels = [min_pixels.to_s.to_i, 0].max
    @max_pixels = [max_pixels.to_s.to_i, 1].max
    @min_opaque_fraction = [[min_opaque_fraction.to_f, 0.0].max, 1.0].min
    @min_visual_variation = [[min_visual_variation.to_f, 0.0].max, 1.0].min
    @validate_visual_content = validate_visual_content
    @visual_analyzer = visual_analyzer
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

    visual = inspect_visual_content(data, width: width, height: height) if validate_visual_content
    if visual && !visual.ok?
      return failure(
        visual.error_type,
        visual.error_message,
        format_info: format_info,
        pixels: pixels,
        sha256: sha256,
        opaque_fraction: visual.opaque_fraction,
        visual_variation: visual.visual_variation,
        color_count: visual.color_count
      )
    end

    if visual && visual.opaque_fraction.to_f < min_opaque_fraction
      return failure(
        'image_transparent',
        "La imagen solo tiene #{(visual.opaque_fraction.to_f * 100).round(1)}% de cobertura opaca; se requiere al menos #{(min_opaque_fraction * 100).round(1)}%.",
        format_info: format_info,
        pixels: pixels,
        sha256: sha256,
        opaque_fraction: visual.opaque_fraction,
        visual_variation: visual.visual_variation,
        color_count: visual.color_count
      )
    end

    if visual && (visual.color_count.to_i <= 1 || visual.visual_variation.to_f < min_visual_variation)
      return failure(
        'image_blank',
        'La imagen es monocroma o no contiene suficiente variacion visual para servir como portada.',
        format_info: format_info,
        pixels: pixels,
        sha256: sha256,
        opaque_fraction: visual.opaque_fraction,
        visual_variation: visual.visual_variation,
        color_count: visual.color_count
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
      sha256: sha256,
      opaque_fraction: visual&.opaque_fraction,
      visual_variation: visual&.visual_variation,
      color_count: visual&.color_count
    )
  end

  private

  attr_reader :min_width, :min_height, :min_pixels, :max_pixels,
              :min_opaque_fraction, :min_visual_variation, :validate_visual_content,
              :visual_analyzer

  def binary_string(value)
    value.to_s.dup.force_encoding(Encoding::BINARY)
  end

  def detect_format(data)
    jpeg_info(data) || png_info(data) || gif_info(data) || webp_info(data)
  end

  def inspect_visual_content(data, width:, height:)
    transparent_png = transparent_grayscale_png_metrics(data, width: width, height: height)
    return transparent_png if transparent_png

    analyzer = visual_analyzer || method(:mini_magick_visual_metrics)
    analyzer.call(data, width: width, height: height)
  rescue Timeout::Error => e
    VisualMetrics.new(
      ok?: false,
      error_type: 'image_visual_inspection_timeout',
      error_message: e.message
    )
  rescue MiniMagick::Invalid => e
    VisualMetrics.new(ok?: false, error_type: 'invalid_image', error_message: e.message)
  rescue MiniMagick::Error, SystemCallError => e
    VisualMetrics.new(
      ok?: false,
      error_type: 'image_visual_inspection_failed',
      error_message: e.message
    )
  end

  # Songkick sometimes returns a standards-compliant 1-bit PNG whose tRNS
  # value makes every decoded pixel transparent. Decode that PNG content (not
  # its compressed byte size) before invoking ImageMagick so this known empty
  # placeholder is rejected even when the ImageMagick executable is absent.
  def transparent_grayscale_png_metrics(data, width:, height:)
    return unless data.start_with?(PNG_SIGNATURE)

    chunks = png_chunks(data)
    ihdr = chunks.find { |chunk| chunk[:type] == 'IHDR' }&.fetch(:data, nil)
    transparency = chunks.find { |chunk| chunk[:type] == 'tRNS' }&.fetch(:data, nil)
    return unless ihdr&.bytesize == 13 && transparency&.bytesize == 2

    decoded_width, decoded_height, bit_depth, color_type, compression, filter_method, interlace = ihdr.unpack('N2C5')
    return unless decoded_width == width && decoded_height == height
    return unless color_type == 0 && [1, 2, 4, 8, 16].include?(bit_depth)
    return unless compression.zero? && filter_method.zero? && interlace.zero?

    idat = chunks.select { |chunk| chunk[:type] == 'IDAT' }.map { |chunk| chunk[:data] }.join
    return if idat.empty?

    row_bytes = ((width * bit_depth) + 7) / 8
    expected_raw_bytes = height * (row_bytes + 1)
    return if expected_raw_bytes > MAX_INLINE_PNG_DECODE_BYTES

    rows = unfiltered_png_rows(
      bounded_zlib_inflate(idat, max_bytes: expected_raw_bytes),
      width: width,
      height: height,
      bit_depth: bit_depth
    )
    transparent_sample = transparency.unpack1('n')
    samples = rows.flat_map { |row| grayscale_png_samples(row, width: width, bit_depth: bit_depth) }
    return unless samples.size == width * height
    return unless samples.all? { |sample| sample == transparent_sample }

    VisualMetrics.new(
      ok?: true,
      width: width,
      height: height,
      opaque_fraction: 0.0,
      visual_variation: 0.0,
      color_count: 1
    )
  rescue Zlib::Error, ArgumentError
    nil
  end

  def bounded_zlib_inflate(compressed, max_bytes:)
    output = String.new(encoding: Encoding::BINARY)
    inflater = Zlib::Inflate.new
    inflater.inflate(compressed) do |chunk|
      raise ArgumentError, 'PNG expandido por encima del limite.' if output.bytesize + chunk.bytesize > max_bytes

      output << chunk
    end
    output
  ensure
    inflater&.close
  end

  def png_chunks(data)
    chunks = []
    offset = PNG_SIGNATURE.bytesize
    while offset + 12 <= data.bytesize
      length = uint32_be(data, offset)
      break unless length

      chunk_end = offset + 12 + length
      break if chunk_end > data.bytesize

      chunks << {
        type: data.byteslice(offset + 4, 4).to_s,
        data: data.byteslice(offset + 8, length)
      }
      offset = chunk_end
    end
    chunks
  end

  def unfiltered_png_rows(raw, width:, height:, bit_depth:)
    row_bytes = ((width * bit_depth) + 7) / 8
    bytes_per_pixel = [((bit_depth + 7) / 8), 1].max
    expected_size = height * (row_bytes + 1)
    raise ArgumentError, 'PNG truncado.' unless raw.bytesize == expected_size

    previous = Array.new(row_bytes, 0)
    offset = 0
    Array.new(height) do
      filter_type = raw.getbyte(offset)
      offset += 1
      row = raw.byteslice(offset, row_bytes).bytes
      offset += row_bytes
      apply_png_filter!(row, previous, filter_type, bytes_per_pixel)
      previous = row
      row
    end
  end

  def apply_png_filter!(row, previous, filter_type, bytes_per_pixel)
    row.each_index do |index|
      left = index >= bytes_per_pixel ? row[index - bytes_per_pixel] : 0
      above = previous[index].to_i
      upper_left = index >= bytes_per_pixel ? previous[index - bytes_per_pixel].to_i : 0
      predictor =
        case filter_type
        when 0 then 0
        when 1 then left
        when 2 then above
        when 3 then ((left + above) / 2).floor
        when 4 then paeth_predictor(left, above, upper_left)
        else raise ArgumentError, 'Filtro PNG no soportado.'
        end
      row[index] = (row[index] + predictor) & 0xFF
    end
  end

  def paeth_predictor(left, above, upper_left)
    estimate = left + above - upper_left
    distances = [(estimate - left).abs, (estimate - above).abs, (estimate - upper_left).abs]
    [left, above, upper_left][distances.index(distances.min)]
  end

  def grayscale_png_samples(row, width:, bit_depth:)
    return row.each_slice(2).first(width).map { |bytes| bytes.pack('C*').unpack1('n') } if bit_depth == 16
    return row.first(width) if bit_depth == 8

    mask = (1 << bit_depth) - 1
    samples_per_byte = 8 / bit_depth
    row.flat_map do |byte|
      samples_per_byte.times.map do |sample_index|
        shift = 8 - (bit_depth * (sample_index + 1))
        (byte >> shift) & mask
      end
    end.first(width)
  end

  def mini_magick_visual_metrics(data, width:, height:)
    configured_timeout = MiniMagick.timeout
    if configured_timeout.nil? || configured_timeout.to_f > VISUAL_INSPECTION_TIMEOUT_SECONDS
      MiniMagick.timeout = VISUAL_INSPECTION_TIMEOUT_SECONDS
    end
    image = MiniMagick::Image.read(data)
    decoded_width = image.width.to_i
    decoded_height = image.height.to_i
    unless decoded_width == width && decoded_height == height
      return VisualMetrics.new(
        ok?: false,
        width: decoded_width,
        height: decoded_height,
        error_type: 'invalid_image',
        error_message: "Las dimensiones decodificadas #{decoded_width}x#{decoded_height} no coinciden con la cabecera #{width}x#{height}."
      )
    end

    sample_width, sample_height = visual_sample_dimensions(width, height)
    image.resize("#{sample_width}x#{sample_height}!")
    pixels = image.get_pixels('RGBA').flatten(1)
    return VisualMetrics.new(ok?: false, error_type: 'invalid_image', error_message: 'No se pudieron decodificar pixeles visibles.') if pixels.empty?

    opaque_fraction = pixels.sum { |pixel| pixel.fetch(3, 255).to_f / 255.0 } / pixels.size
    composited = pixels.map { |pixel| composite_on_white(pixel) }
    variation = rgb_variation(composited)
    color_count = composited.uniq.size

    VisualMetrics.new(
      ok?: true,
      width: decoded_width,
      height: decoded_height,
      opaque_fraction: opaque_fraction,
      visual_variation: variation,
      color_count: color_count
    )
  ensure
    image&.destroy!
  end

  def visual_sample_dimensions(width, height)
    scale = [VISUAL_SAMPLE_EDGE.to_f / width, VISUAL_SAMPLE_EDGE.to_f / height, 1.0].min
    [[(width * scale).round, 1].max, [(height * scale).round, 1].max]
  end

  def composite_on_white(pixel)
    alpha = pixel.fetch(3, 255).to_f / 255.0
    pixel.first(3).map { |channel| ((channel.to_f * alpha) + (255.0 * (1.0 - alpha))).round }
  end

  def rgb_variation(pixels)
    channel_variances = 3.times.map do |channel_index|
      values = pixels.map { |pixel| pixel.fetch(channel_index).to_f }
      mean = values.sum / values.size
      values.sum { |value| (value - mean)**2 } / values.size
    end
    Math.sqrt(channel_variances.sum / channel_variances.size) / 255.0
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

  def failure(
    error_type,
    message,
    format_info: nil,
    pixels: nil,
    sha256: nil,
    opaque_fraction: nil,
    visual_variation: nil,
    color_count: nil
  )
    Result.new(
      ok?: false,
      format: format_info&.format,
      content_type: format_info&.content_type,
      extension: format_info&.extension,
      width: format_info&.width,
      height: format_info&.height,
      pixels: pixels,
      sha256: sha256,
      opaque_fraction: opaque_fraction,
      visual_variation: visual_variation,
      color_count: color_count,
      error_type: error_type,
      error_message: message
    )
  end
end
