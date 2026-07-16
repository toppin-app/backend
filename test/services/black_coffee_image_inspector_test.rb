require 'test_helper'

class BlackCoffeeImageInspectorTest < ActiveSupport::TestCase
  setup do
    @inspector = BlackCoffeeImageInspector.new(
      min_width: 0,
      min_height: 0,
      min_pixels: 0
    )
  end

  test 'detects jpeg dimensions from start of frame bytes' do
    result = @inspector.call(jpeg_bytes(width: 1_024, height: 768))

    assert result.ok?
    assert_equal 'jpeg', result.format
    assert_equal 'image/jpeg', result.content_type
    assert_equal 1_024, result.width
    assert_equal 768, result.height
  end

  test 'detects png dimensions from ihdr bytes' do
    result = @inspector.call(png_bytes(width: 640, height: 480))

    assert result.ok?
    assert_equal 'png', result.format
    assert_equal 'image/png', result.content_type
    assert_equal 640, result.width
    assert_equal 480, result.height
  end

  test 'detects gif logical screen dimensions' do
    result = @inspector.call(gif_bytes(width: 500, height: 300))

    assert result.ok?
    assert_equal 'gif', result.format
    assert_equal 'image/gif', result.content_type
    assert_equal 500, result.width
    assert_equal 300, result.height
  end

  test 'detects webp extended canvas dimensions' do
    result = @inspector.call(webp_bytes(width: 1_280, height: 720))

    assert result.ok?
    assert_equal 'webp', result.format
    assert_equal 'image/webp', result.content_type
    assert_equal 1_280, result.width
    assert_equal 720, result.height
  end

  test 'rejects dimensions that could trigger excessive image processing' do
    inspector = BlackCoffeeImageInspector.new(
      min_width: 0,
      min_height: 0,
      min_pixels: 0,
      max_pixels: 1_000_000
    )

    result = inspector.call(jpeg_bytes(width: 2_000, height: 2_000))

    assert_not result.ok?
    assert_equal 'image_dimensions_too_large', result.error_type
  end

  private

  def jpeg_bytes(width:, height:)
    body = "\xFF\xD8\xFF\xC0".b
    body << [17].pack('n')
    body << [8].pack('C')
    body << [height, width].pack('n2')
    body << [3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0].pack('C*')
    body << "\xFF\xD9".b
    body
  end

  def png_bytes(width:, height:)
    ihdr = [width, height, 8, 2, 0, 0, 0].pack('N2C5')
    BlackCoffeeImageInspector::PNG_SIGNATURE +
      [ihdr.bytesize].pack('N') + 'IHDR'.b + ihdr + [0].pack('N')
  end

  def gif_bytes(width:, height:)
    'GIF89a'.b + [width, height].pack('v2') + "\x00\x00\x00".b
  end

  def webp_bytes(width:, height:)
    payload = "\x00\x00\x00\x00".b + uint24_le(width - 1) + uint24_le(height - 1)
    chunk = 'VP8X'.b + [payload.bytesize].pack('V') + payload
    'RIFF'.b + [4 + chunk.bytesize].pack('V') + 'WEBP'.b + chunk
  end

  def uint24_le(value)
    [value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF].pack('C3')
  end
end
