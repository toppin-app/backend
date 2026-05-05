require 'digest'

module BlackCoffeeTaxonomy
  SUBCATEGORIES = {
    'restaurante' => [
      {
        name: 'japonesa',
        label: 'Cocina japonesa',
        google_types: %w[
          japanese_curry_restaurant japanese_izakaya_restaurant japanese_restaurant ramen_restaurant
          sushi_restaurant tonkatsu_restaurant yakiniku_restaurant yakitori_restaurant
        ],
        keywords: %w[sushi ramen izakaya japones japonesa japon maki yakitori]
      },
      {
        name: 'comida_china',
        label: 'Cocina china',
        google_types: %w[cantonese_restaurant chinese_noodle_restaurant chinese_restaurant dim_sum_restaurant],
        keywords: ['chino', 'china', 'chinese', 'wok', 'dim sum']
      },
      {
        name: 'asiatica',
        label: 'Cocina asiatica',
        google_types: %w[
          asian_fusion_restaurant asian_restaurant dumpling_restaurant filipino_restaurant hot_pot_restaurant
          indonesian_restaurant korean_barbecue_restaurant korean_restaurant malaysian_restaurant noodle_shop
          taiwanese_restaurant thai_restaurant vietnamese_restaurant
        ],
        keywords: %w[asiatico asiatica asian coreano coreana korean thai tailandes vietnamita vietnamese noodles]
      },
      {
        name: 'india',
        label: 'Cocina india',
        google_types: %w[indian_restaurant north_indian_restaurant south_indian_restaurant pakistani_restaurant],
        keywords: %w[indian india hindu curry tandoori pakistani]
      },
      {
        name: 'italiana',
        label: 'Cocina italiana',
        google_types: %w[italian_restaurant pizza_restaurant pizza_delivery],
        keywords: %w[italian italiana italiano pizza pizzeria trattoria pasta]
      },
      {
        name: 'mexicana',
        label: 'Cocina mexicana',
        google_types: %w[burrito_restaurant mexican_restaurant taco_restaurant tex_mex_restaurant],
        keywords: %w[mexican mexicana mexicano tacos taco taqueria burrito texmex]
      },
      {
        name: 'mediterranea',
        label: 'Cocina mediterranea',
        google_types: %w[
          greek_restaurant lebanese_restaurant mediterranean_restaurant middle_eastern_restaurant
          moroccan_restaurant seafood_restaurant turkish_restaurant
        ],
        keywords: %w[mediterraneo mediterranea griego libanes marisqueria arroceria paella seafood turco moroccan]
      },
      {
        name: 'tapas',
        label: 'Tapas y raciones',
        google_types: %w[spanish_restaurant tapas_restaurant],
        keywords: %w[tapas taberna taperia pinchos pintxos raciones vermut]
      },
      {
        name: 'hamburgueseria',
        label: 'Hamburgueserias',
        google_types: %w[hamburger_restaurant],
        keywords: %w[burger burgers hamburguesa hamburgueseria smash]
      },
      {
        name: 'brunch',
        label: 'Brunch y desayunos',
        google_types: %w[breakfast_restaurant brunch_restaurant diner],
        keywords: %w[brunch breakfast desayuno desayunos]
      },
      {
        name: 'americana',
        label: 'Cocina americana',
        google_types: %w[american_restaurant barbecue_restaurant southwestern_us_restaurant],
        keywords: %w[american americana bbq barbecue diner texan sureño]
      },
      {
        name: 'parrilla',
        label: 'Parrilla y carnes',
        google_types: %w[argentinian_restaurant brazilian_restaurant steak_house],
        keywords: %w[steakhouse asador parrilla brasa brasas carne carnes argentino argentina churrasco]
      },
      {
        name: 'latina',
        label: 'Cocina latina',
        google_types: %w[
          caribbean_restaurant chilean_restaurant colombian_restaurant cuban_restaurant latin_american_restaurant
          peruvian_restaurant south_american_restaurant
        ],
        keywords: %w[peru peruano peruana ceviche pisco latino latina latinoamericano sudamericano]
      },
      {
        name: 'vegetariana_vegana',
        label: 'Vegetariana y vegana',
        google_types: %w[vegan_restaurant vegetarian_restaurant salad_shop],
        keywords: %w[vegano vegana vegetariano vegetariana plantbased saludable organico organica]
      }
    ],
    'hotel' => [
      { name: 'hotel', label: 'Hotel', google_types: %w[hotel lodging], keywords: %w[hotel alojamiento] },
      { name: 'hostal', label: 'Hostal', google_types: %w[hostel inn], keywords: %w[hostal hostel inn] },
      { name: 'boutique', label: 'Boutique', google_types: [], keywords: %w[boutique design encanto romantico] },
      { name: 'business', label: 'Business', google_types: %w[extended_stay_hotel], keywords: %w[business negocios ejecutivo congress] },
      { name: 'escapada', label: 'Escapada', google_types: %w[guest_house private_guest_room cottage farmstay], keywords: %w[escapada romantico relax rural casa] },
      { name: 'resort', label: 'Resort', google_types: %w[resort_hotel], keywords: %w[resort spa beach club vacaciones] },
      { name: 'bed_and_breakfast', label: 'Bed and breakfast', google_types: %w[bed_and_breakfast], keywords: %w[bed breakfast bnb desayuno] },
      { name: 'motel', label: 'Motel', google_types: %w[motel], keywords: %w[motel carretera] }
    ],
    'pub' => [
      { name: 'cocteleria', label: 'Cocteleria', google_types: %w[cocktail_bar], keywords: %w[coctel cocteleria cocktail cocktails mixology speakeasy] },
      { name: 'cerveceria', label: 'Cerveceria', google_types: %w[beer_garden brewery brewpub pub], keywords: %w[cerveceria cerveza beer craft ipa pub] },
      { name: 'vinoteca', label: 'Vinoteca', google_types: %w[wine_bar winery], keywords: %w[vino wine vinoteca bodega vermut] },
      { name: 'tapas', label: 'Tapas y raciones', google_types: %w[bar_and_grill gastropub], keywords: %w[tapas taberna gastrobar raciones] },
      { name: 'rooftop', label: 'Rooftop', google_types: [], keywords: %w[rooftop terraza azotea views vistas atardecer] },
      { name: 'lounge', label: 'Lounge', google_types: %w[lounge_bar], keywords: %w[lounge chill chillout sofa premium] },
      { name: 'sports_bar', label: 'Sports bar', google_types: %w[sports_bar], keywords: %w[sports sport futbol partido pantalla] }
    ],
    'cine' => [
      { name: 'cine', label: 'Cine', google_types: %w[movie_theater], keywords: %w[cine cinema movie theater peliculas] }
    ],
    'cafeteria' => [
      { name: 'cafeteria', label: 'Cafeteria', google_types: %w[cafe cafeteria], keywords: %w[cafe cafeteria espresso] },
      { name: 'artesanal', label: 'Cafe de especialidad', google_types: %w[coffee_roastery coffee_shop coffee_stand], keywords: %w[especialidad artesanal specialty coffee tostador] },
      { name: 'panaderia', label: 'Panaderia', google_types: %w[bagel_shop bakery], keywords: %w[panaderia bakery pan masa madre croissant] },
      { name: 'pasteleria', label: 'Pasteleria', google_types: %w[cake_shop dessert_shop pastry_shop], keywords: %w[pasteleria pastel tartas dessert pastry dulce] },
      { name: 'heladeria', label: 'Heladeria', google_types: %w[ice_cream_shop], keywords: %w[helado heladeria ice cream gelato] },
      { name: 'te', label: 'Te y meriendas', google_types: %w[tea_house tea_store], keywords: %w[te tea matcha merienda] }
    ],
    'concierto' => [
      { name: 'indie', label: 'Indie', google_types: %w[concert_hall live_music_venue performing_arts_theater], keywords: %w[indie alternativo banda directo] },
      { name: 'pop_rock', label: 'Pop y rock', google_types: %w[concert_hall live_music_venue], keywords: %w[pop rock banda tributo] },
      { name: 'acustico', label: 'Acustico', google_types: %w[auditorium performing_arts_theater], keywords: %w[acustico acustica unplugged piano] },
      { name: 'musical', label: 'Musical', google_types: %w[event_venue], keywords: %w[musical musica live concierto] }
    ],
    'festival' => [
      { name: 'festival', label: 'Festival', google_types: %w[event_venue], keywords: %w[festival feria evento] },
      { name: 'musical', label: 'Musical', google_types: %w[amphitheatre concert_hall live_music_venue], keywords: %w[musica musical concierto live dj] },
      { name: 'gastronomico', label: 'Gastronomico', google_types: %w[food_court farmers_market market], keywords: %w[food foodtruck gastronomico gastronomia streetfood] },
      { name: 'urbano', label: 'Urbano', google_types: [], keywords: %w[urbano street market pop up popup] },
      { name: 'cultural', label: 'Cultural', google_types: %w[cultural_center performing_arts_theater auditorium], keywords: %w[cultural cultura teatro arte exposicion] },
      { name: 'convencion', label: 'Convencion', google_types: %w[convention_center], keywords: %w[convencion congreso expo convention] }
    ],
    'discoteca' => [
      { name: 'discoteca', label: 'Discoteca', google_types: %w[night_club dance_hall], keywords: %w[discoteca nightclub noche dance] },
      { name: 'club', label: 'Club', google_types: %w[night_club], keywords: %w[club dance house techno] },
      { name: 'electro', label: 'Electronica', google_types: [], keywords: %w[electro electronica techno house edm] },
      { name: 'lounge', label: 'Lounge', google_types: %w[lounge_bar], keywords: %w[lounge chill premium sofa] },
      { name: 'rooftop', label: 'Rooftop', google_types: [], keywords: %w[rooftop terraza azotea vistas] }
    ],
    'deportivo' => [
      { name: 'deporte', label: 'Actividad deportiva', google_types: %w[sports_activity_location sports_complex sports_club], keywords: %w[deporte deportivo sport sports] },
      { name: 'gimnasio', label: 'Gimnasio y fitness', google_types: %w[fitness_center gym wellness_center], keywords: %w[gimnasio gym fitness crossfit entrenamiento] },
      { name: 'padel', label: 'Padel', google_types: [], keywords: %w[padel paddle] },
      { name: 'outdoor', label: 'Outdoor', google_types: %w[athletic_field playground race_course], keywords: %w[outdoor aire libre running rugby futbol campo] },
      { name: 'climbing', label: 'Escalada', google_types: [], keywords: %w[climbing escalada boulder rocódromo rocodromo] },
      { name: 'tenis', label: 'Tenis', google_types: %w[tennis_court], keywords: %w[tenis tennis] },
      { name: 'piscina', label: 'Piscina', google_types: %w[swimming_pool], keywords: %w[piscina swimming pool natacion] },
      { name: 'golf', label: 'Golf', google_types: %w[golf_course indoor_golf_course], keywords: %w[golf] },
      { name: 'arena', label: 'Estadio y arena', google_types: %w[arena stadium], keywords: %w[arena estadio stadium] }
    ],
    'escape_room' => [
      { name: 'escape_room', label: 'Escape room', google_types: %w[amusement_center], keywords: ['escape room', 'escape'] },
      { name: 'misterio', label: 'Misterio', google_types: [], keywords: %w[misterio detective crimen secreto enigma] },
      { name: 'terror', label: 'Terror', google_types: [], keywords: %w[terror horror zombie miedo oscuro paranormal] },
      { name: 'aventura', label: 'Aventura', google_types: [], keywords: %w[aventura quest mision tesoro jungla pirata] },
      { name: 'familiar', label: 'Familiar', google_types: [], keywords: %w[familiar niños ninos familia kids] }
    ]
  }.freeze

  LEGACY_ALIASES = {
    ['restaurante', 'restaurante'] => nil,
    ['pub', 'pub'] => nil,
    ['bar', 'cerveceria'] => ['pub', 'cerveceria'],
    ['bar', 'cocteleria'] => ['pub', 'cocteleria'],
    ['bar', 'tapas'] => ['pub', 'tapas'],
    ['escape_room', 'escape room'] => ['escape_room', 'escape_room'],
    ['discoteca', 'club'] => ['discoteca', 'club']
  }.freeze

  module_function

  def subcategories_for(category)
    SUBCATEGORIES.fetch(category.to_s, [])
  end

  def subcategory_names(category)
    subcategories_for(category).map { |entry| entry.fetch(:name) }
  end

  def valid_subcategory?(category, name)
    name.to_s.blank? || subcategory_names(category).include?(normalize_name(name))
  end

  def option_for(category, name)
    normalized = normalize_name(name)
    subcategories_for(category).find { |entry| entry.fetch(:name) == normalized }
  end

  def label_for(category, name)
    option_for(category, name)&.fetch(:label, nil) || name.to_s.tr('_', ' ').presence
  end

  def subcategory_options(category = nil)
    categories = category.present? ? [category.to_s] : SUBCATEGORIES.keys
    categories.flat_map do |category_name|
      subcategories_for(category_name).map do |entry|
        entry.merge(category: category_name)
      end
    end
  end

  def subcategory_id(category, name)
    "sub_#{Digest::SHA256.hexdigest("#{category}:#{normalize_name(name)}")[0, 12]}"
  end

  def subcategory_for_google_place(place, category:, fallback: nil)
    normalized_category = category.to_s
    tags = google_tags_for_place(place)
    text = normalized_match_text(
      [
        nested_place_value(place, 'displayName', 'text'),
        nested_place_value(place, 'primaryTypeDisplayName', 'text'),
        place_value(place, 'primaryType'),
        tags.join(' ')
      ].compact.join(' ')
    )

    by_type = subcategories_for(normalized_category).find do |entry|
      (Array(entry[:google_types]) & tags).any?
    end
    return by_type[:name] if by_type

    by_keyword = subcategories_for(normalized_category).find do |entry|
      Array(entry[:keywords]).any? { |keyword| text.include?(normalized_match_text(keyword)) }
    end
    return by_keyword[:name] if by_keyword

    normalize_name(fallback)
  end

  def google_tags_for_place(place)
    [place_value(place, 'primaryType'), Array(place_value(place, 'types'))]
      .flatten
      .compact
      .map { |tag| normalize_google_tag(tag) }
      .reject(&:blank?)
      .uniq
  end

  def google_primary_type_for_place(place)
    normalize_google_tag(place_value(place, 'primaryType'))
  end

  def google_secondary_tags_for_place(place)
    primary = google_primary_type_for_place(place)
    google_tags_for_place(place).reject { |tag| tag == primary }
  end

  def fallback_internal_tags(category, subcategory)
    [category, subcategory].map { |tag| normalize_google_tag(tag) }.reject(&:blank?).uniq
  end

  def normalize_name(value)
    value.to_s.strip.downcase.presence
  end

  def normalize_google_tag(value)
    I18n.transliterate(value.to_s).strip.downcase.gsub(/[^a-z0-9_]+/, '_').gsub(/\A_+|_+\z/, '')
  rescue StandardError
    value.to_s.strip.downcase
  end

  def normalized_match_text(value)
    I18n.transliterate(value.to_s).downcase
  rescue StandardError
    value.to_s.downcase
  end

  def place_value(place, key)
    return unless place.respond_to?(:[])

    place[key] || place[key.to_sym]
  end

  def nested_place_value(place, key, nested_key)
    value = place_value(place, key)
    return unless value.respond_to?(:[])

    value[nested_key] || value[nested_key.to_sym]
  end
end
