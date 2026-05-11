require 'i18n'

class GooglePlacesRegionValidator
  ValidationResult = Struct.new(:valid, :reason, :state, :province, keyword_init: true) do
    def valid?
      valid
    end
  end

  REGION_RULES = {
    'andalucia' => {
      aliases: ['andalucia', 'andalucía', 'andalusia'],
      provinces: ['almeria', 'almería', 'cadiz', 'cádiz', 'cordoba', 'córdoba', 'granada', 'huelva', 'jaen', 'jaén', 'malaga', 'málaga', 'sevilla']
    },
    'aragon' => {
      aliases: ['aragon', 'aragón'],
      provinces: ['huesca', 'teruel', 'zaragoza']
    },
    'asturias' => {
      aliases: ['asturias', 'principado de asturias'],
      provinces: ['asturias']
    },
    'islas_baleares' => {
      aliases: ['islas baleares', 'illes balears', 'baleares', 'balearic islands'],
      provinces: ['islas baleares', 'illes balears', 'baleares']
    },
    'canarias' => {
      aliases: ['canarias', 'islas canarias', 'canary islands'],
      provinces: ['las palmas', 'santa cruz de tenerife']
    },
    'cantabria' => {
      aliases: ['cantabria'],
      provinces: ['cantabria']
    },
    'castilla_la_mancha' => {
      aliases: ['castilla la mancha', 'castilla-la mancha', 'castilla-la-mancha'],
      provinces: ['albacete', 'ciudad real', 'cuenca', 'guadalajara', 'toledo']
    },
    'castilla_y_leon' => {
      aliases: ['castilla y leon', 'castilla y león', 'castile and leon', 'castile and león'],
      provinces: ['avila', 'ávila', 'burgos', 'leon', 'león', 'palencia', 'salamanca', 'segovia', 'soria', 'valladolid', 'zamora']
    },
    'cataluna' => {
      aliases: ['cataluna', 'cataluña', 'catalunya', 'catalonia'],
      provinces: ['barcelona', 'girona', 'gerona', 'lleida', 'lerida', 'lérida', 'tarragona']
    },
    'comunidad_valenciana' => {
      aliases: ['comunidad valenciana', 'comunitat valenciana', 'valencian community'],
      provinces: ['valencia', 'valència', 'alicante', 'alacant', 'castellon', 'castellón', 'castello', 'castelló']
    },
    'extremadura' => {
      aliases: ['extremadura'],
      provinces: ['badajoz', 'caceres', 'cáceres']
    },
    'galicia' => {
      aliases: ['galicia', 'galiza'],
      provinces: ['a coruna', 'a Coruña', 'la coruna', 'la Coruña', 'lugo', 'ourense', 'orense', 'pontevedra']
    },
    'comunidad_de_madrid' => {
      aliases: ['comunidad de madrid', 'madrid'],
      provinces: ['madrid']
    },
    'region_de_murcia' => {
      aliases: ['region de murcia', 'región de murcia', 'murcia'],
      provinces: ['murcia']
    },
    'navarra' => {
      aliases: ['navarra', 'comunidad foral de navarra', 'navarre'],
      provinces: ['navarra', 'nafarroa']
    },
    'pais_vasco' => {
      aliases: ['pais vasco', 'país vasco', 'euskadi', 'basque country'],
      provinces: ['alava', 'álava', 'araba', 'bizkaia', 'vizcaya', 'gipuzkoa', 'guipuzcoa', 'guipúzcoa']
    },
    'la_rioja' => {
      aliases: ['la rioja', 'rioja'],
      provinces: ['la rioja']
    },
    'ceuta' => {
      aliases: ['ceuta'],
      provinces: ['ceuta']
    },
    'melilla' => {
      aliases: ['melilla'],
      provinces: ['melilla']
    }
  }.freeze

  NORMALIZED_REGION_ALIASES = REGION_RULES.each_with_object({}) do |(slug, rule), memo|
    Array(rule[:aliases]).each { |value| memo[normalize(value)] = slug }
  end.freeze

  NORMALIZED_PROVINCES = REGION_RULES.each_with_object({}) do |(slug, rule), memo|
    Array(rule[:provinces]).each { |value| memo[normalize(value)] = slug }
  end.freeze

  def self.validate(place_or_attrs, region:, strict: true)
    new(region, strict: strict).validate(place_or_attrs)
  end

  def self.normalize(value)
    I18n.transliterate(value.to_s)
        .downcase
        .gsub(/[^a-z0-9]+/, ' ')
        .squeeze(' ')
        .strip
  end

  def initialize(region, strict: true)
    @region = region
    @slug = region.respond_to?(:slug) ? region.slug.to_s : region.to_s
    @strict = strict
  end

  def validate(place_or_attrs)
    country_code = component_value(place_or_attrs, 'country', key: 'shortText').presence ||
                   value_for(place_or_attrs, :country_code).presence
    if country_code.present? && country_code.to_s.upcase != 'ES'
      return result(false, 'country_mismatch', place_or_attrs)
    end

    state = component_value(place_or_attrs, 'administrative_area_level_1').presence ||
            value_for(place_or_attrs, :state).presence
    province = component_value(place_or_attrs, 'administrative_area_level_2').presence ||
               value_for(place_or_attrs, :province).presence

    state_slug = NORMALIZED_REGION_ALIASES[self.class.normalize(state)]
    return result(true, 'state_match', place_or_attrs, state: state, province: province) if state_slug == @slug
    return result(false, 'state_mismatch', place_or_attrs, state: state, province: province) if state_slug.present?

    province_slug = NORMALIZED_PROVINCES[self.class.normalize(province)]
    return result(true, 'province_match', place_or_attrs, state: state, province: province) if province_slug == @slug
    return result(false, 'province_mismatch', place_or_attrs, state: state, province: province) if province_slug.present?

    address_region_result = validate_from_formatted_address(place_or_attrs, state: state, province: province)
    return address_region_result if address_region_result.present?

    result(!@strict, 'unconfirmed_region', place_or_attrs, state: state, province: province)
  end

  private

  def validate_from_formatted_address(place_or_attrs, state:, province:)
    address = value_for(place_or_attrs, :formattedAddress).presence ||
              value_for(place_or_attrs, :formatted_address).presence ||
              value_for(place_or_attrs, :address).presence
    normalized_segments = address.to_s.split(',').map { |segment| self.class.normalize(segment) }.reject(&:blank?)
    return if normalized_segments.blank?

    matched_province = NORMALIZED_PROVINCES.find do |province_name, _slug|
      normalized_segments.any? { |segment| address_segment_matches?(segment, province_name) }
    end
    if matched_province.present?
      province_slug = matched_province.last
      return result(province_slug == @slug, province_slug == @slug ? 'address_province_match' : 'address_province_mismatch', place_or_attrs, state: state, province: province)
    end

    matched_region = NORMALIZED_REGION_ALIASES.find do |region_name, _slug|
      normalized_segments.any? { |segment| address_segment_matches?(segment, region_name) }
    end
    return if matched_region.blank?

    region_slug = matched_region.last
    result(region_slug == @slug, region_slug == @slug ? 'address_state_match' : 'address_state_mismatch', place_or_attrs, state: state, province: province)
  end

  def result(valid, reason, place_or_attrs, state: nil, province: nil)
    ValidationResult.new(
      valid: valid,
      reason: reason,
      state: state.presence || component_value(place_or_attrs, 'administrative_area_level_1').presence || value_for(place_or_attrs, :state),
      province: province.presence || component_value(place_or_attrs, 'administrative_area_level_2').presence || value_for(place_or_attrs, :province)
    )
  end

  def address_segment_matches?(segment, expected_name)
    segment == expected_name || segment.sub(/\A\d{4,5}\s+/, '') == expected_name
  end

  def component_value(place_or_attrs, type, key: 'longText')
    component = Array(value_for(place_or_attrs, :addressComponents) || value_for(place_or_attrs, :address_components)).find do |entry|
      Array(entry_value(entry, :types)).include?(type)
    end
    return if component.blank?

    entry_value(component, key).presence ||
      entry_value(component, :longText).presence ||
      entry_value(component, :shortText).presence
  end

  def value_for(object, key)
    string_key = key.to_s
    if object.respond_to?(:[])
      object[string_key] || object[key]
    elsif object.respond_to?(string_key)
      object.public_send(string_key)
    end
  end

  def entry_value(entry, key)
    return unless entry.respond_to?(:[])

    entry[key.to_s] || entry[key]
  end
end
