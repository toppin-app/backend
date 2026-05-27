require 'test_helper'
require 'ostruct'

class GooglePlacesRegionValidatorTest < ActiveSupport::TestCase
  def valencian_region
    OpenStruct.new(slug: 'comunidad_valenciana', name: 'Comunidad Valenciana')
  end

  def place_with_components(state:, province:, country_code: 'ES')
    {
      'addressComponents' => [
        { 'types' => ['administrative_area_level_1'], 'longText' => state },
        { 'types' => ['administrative_area_level_2'], 'longText' => province },
        { 'types' => ['country'], 'longText' => 'Spain', 'shortText' => country_code }
      ]
    }
  end

  test 'accepts places whose Google state matches the requested autonomous community' do
    place = place_with_components(
      state: 'Comunitat Valenciana',
      province: 'València'
    )

    result = GooglePlacesRegionValidator.validate(place, region: valencian_region)

    assert result.valid?
    assert_equal 'state_match', result.reason
    assert_equal 'Comunitat Valenciana', result.state
  end

  test 'accepts places by province when the state component is missing' do
    place = place_with_components(state: nil, province: 'Alicante')

    result = GooglePlacesRegionValidator.validate(place, region: valencian_region)

    assert result.valid?
    assert_equal 'province_match', result.reason
    assert_equal 'Alicante', result.province
  end

  test 'rejects places from another autonomous community before import continues' do
    place = place_with_components(
      state: 'Región de Murcia',
      province: 'Murcia'
    )

    result = GooglePlacesRegionValidator.validate(place, region: valencian_region)

    refute result.valid?
    assert_equal 'state_mismatch', result.reason
  end

  test 'rejects non Spanish places even if strict mode is disabled' do
    place = place_with_components(
      state: 'Comunitat Valenciana',
      province: 'València',
      country_code: 'FR'
    )

    result = GooglePlacesRegionValidator.validate(
      place,
      region: valencian_region,
      strict: false
    )

    refute result.valid?
    assert_equal 'country_mismatch', result.reason
  end

  test 'uses formatted address as a fallback and honours strict unconfirmed handling' do
    address_place = {
      'formattedAddress' => 'Carrer Major 1, 46001 Valencia, Spain',
      'addressComponents' => [
        { 'types' => ['country'], 'longText' => 'Spain', 'shortText' => 'ES' }
      ]
    }

    result = GooglePlacesRegionValidator.validate(address_place, region: valencian_region)

    assert result.valid?
    assert_equal 'address_province_match', result.reason

    unconfirmed_place = {
      'formattedAddress' => 'Carrer desconegut, Spain',
      'addressComponents' => [
        { 'types' => ['country'], 'longText' => 'Spain', 'shortText' => 'ES' }
      ]
    }

    strict_result = GooglePlacesRegionValidator.validate(unconfirmed_place, region: valencian_region)
    relaxed_result = GooglePlacesRegionValidator.validate(
      unconfirmed_place,
      region: valencian_region,
      strict: false
    )

    refute strict_result.valid?
    assert_equal 'unconfirmed_region', strict_result.reason
    assert relaxed_result.valid?
    assert_equal 'unconfirmed_region', relaxed_result.reason
  end
end
