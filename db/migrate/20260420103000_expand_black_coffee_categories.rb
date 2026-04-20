require 'digest'

class ExpandBlackCoffeeCategories < ActiveRecord::Migration[6.0]
  LEGACY_BAR_CATEGORY = 'bar'.freeze
  PUB_CATEGORY = 'pub'.freeze
  DISCOTECA_CATEGORY = 'discoteca'.freeze
  NEW_ONLY_CATEGORIES = %w[hotel concierto festival deportivo].freeze
  NIGHTLIFE_CATEGORIES = [PUB_CATEGORY, DISCOTECA_CATEGORY].freeze

  DISCOTECA_VENUE_OVERRIDES = {
    'v20' => { subcategory: 'rooftop' },
    'v21' => { subcategory: 'electro' },
    'v35' => { subcategory: 'club' },
    'v53' => { subcategory: 'rooftop' },
    'v64' => { subcategory: 'rooftop' },
    'v69' => { subcategory: 'lounge' },
    'v80' => { subcategory: 'club' }
  }.freeze

  DISCOTECA_TO_BAR_SUBCATEGORY = {
    'rooftop' => 'cocteleria',
    'electro' => 'cocteleria',
    'club' => 'cocteleria',
    'lounge' => 'cocteleria'
  }.freeze

  def self.schedule_entry(day, slots, closed: false)
    {
      'day' => day,
      'closed' => closed,
      'slots' => slots
    }
  end

  def self.full_week_schedule(open_time, close_time)
    %w[L M X J V S D].map do |day|
      schedule_entry(day, [{ 'open' => open_time, 'close' => close_time }])
    end
  end

  def self.evening_week_schedule(open_time, close_time)
    [
      schedule_entry('L', [], closed: true),
      schedule_entry('M', [], closed: true),
      schedule_entry('X', [{ 'open' => open_time, 'close' => close_time }]),
      schedule_entry('J', [{ 'open' => open_time, 'close' => close_time }]),
      schedule_entry('V', [{ 'open' => open_time, 'close' => '01:00' }]),
      schedule_entry('S', [{ 'open' => open_time, 'close' => '01:00' }]),
      schedule_entry('D', [{ 'open' => open_time, 'close' => '22:30' }])
    ]
  end

  def self.weekend_schedule(open_time, close_time, sunday_close:)
    [
      schedule_entry('L', [], closed: true),
      schedule_entry('M', [], closed: true),
      schedule_entry('X', [], closed: true),
      schedule_entry('J', [], closed: true),
      schedule_entry('V', [{ 'open' => open_time, 'close' => close_time }]),
      schedule_entry('S', [{ 'open' => open_time, 'close' => close_time }]),
      schedule_entry('D', [{ 'open' => open_time, 'close' => sunday_close }])
    ]
  end

  NEW_VENUES = [
    {
      'id' => 'v81',
      'name' => 'Hotel Valencia Congress',
      'category' => 'hotel',
      'subcategory' => 'business',
      'description' => 'Hotel moderno con spa, rooftop y escapadas premium pensadas para una cita sin complicaciones.',
      'location' => {
        'address' => 'Carrer de Botiguers 49',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.5034, 'longitude' => -0.4398 }
      },
      'favoritesCount' => 1684,
      'featured' => true,
      'tags' => ['hotel', 'spa', 'rooftop', 'escapada'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-hotel-81a/900/700',
        'https://picsum.photos/seed/blackcoffee-hotel-81b/900/700',
        'https://picsum.photos/seed/blackcoffee-hotel-81c/900/700'
      ],
      'schedule' => full_week_schedule('00:00', '23:59')
    },
    {
      'id' => 'v82',
      'name' => 'AZZ Valencia Tactica',
      'category' => 'hotel',
      'subcategory' => 'boutique',
      'description' => 'Ambiente elegante, habitaciones minimalistas y desayuno tardio para planes tranquilos en pareja.',
      'location' => {
        'address' => 'Carrer Botiguers 17',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.5017, 'longitude' => -0.4366 }
      },
      'favoritesCount' => 1210,
      'featured' => false,
      'tags' => ['hotel', 'boutique', 'relax', 'late checkout'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-hotel-82a/900/700',
        'https://picsum.photos/seed/blackcoffee-hotel-82b/900/700',
        'https://picsum.photos/seed/blackcoffee-hotel-82c/900/700'
      ],
      'schedule' => full_week_schedule('00:00', '23:59')
    },
    {
      'id' => 'v83',
      'name' => 'Posadas de Espana Paterna',
      'category' => 'hotel',
      'subcategory' => 'escapada',
      'description' => 'Un hotel comodo y muy resolutivo para cenas con noche fuera y desconexion total.',
      'location' => {
        'address' => 'Avinguda Leonardo da Vinci 1',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.5092, 'longitude' => -0.4435 }
      },
      'favoritesCount' => 984,
      'featured' => false,
      'tags' => ['hotel', 'escapada', 'parking', 'pareja'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-hotel-83a/900/700',
        'https://picsum.photos/seed/blackcoffee-hotel-83b/900/700',
        'https://picsum.photos/seed/blackcoffee-hotel-83c/900/700'
      ],
      'schedule' => full_week_schedule('00:00', '23:59')
    },
    {
      'id' => 'v84',
      'name' => 'Sala Republica Live',
      'category' => 'concierto',
      'subcategory' => 'indie',
      'description' => 'Conciertos de formato medio, buena acustica y cartel cambiante para noches con energia.',
      'location' => {
        'address' => 'Carrer Ciutat de Sevilla 28',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.5058, 'longitude' => -0.4423 }
      },
      'favoritesCount' => 1502,
      'featured' => true,
      'tags' => ['concierto', 'indie', 'directo', 'noche'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-concierto-84a/900/700',
        'https://picsum.photos/seed/blackcoffee-concierto-84b/900/700',
        'https://picsum.photos/seed/blackcoffee-concierto-84c/900/700'
      ],
      'schedule' => evening_week_schedule('18:00', '23:30')
    },
    {
      'id' => 'v85',
      'name' => 'Kinepolis Sessions',
      'category' => 'concierto',
      'subcategory' => 'pop_rock',
      'description' => 'Citas musicales junto a Heron City con artistas nacionales, aftermovie vibes y mucha visibilidad.',
      'location' => {
        'address' => 'Avinguda Francisco Tomas y Valiente 6',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.4895, 'longitude' => -0.4149 }
      },
      'favoritesCount' => 1127,
      'featured' => false,
      'tags' => ['concierto', 'pop rock', 'festival vibe', 'live'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-concierto-85a/900/700',
        'https://picsum.photos/seed/blackcoffee-concierto-85b/900/700',
        'https://picsum.photos/seed/blackcoffee-concierto-85c/900/700'
      ],
      'schedule' => [
        schedule_entry('L', [], closed: true),
        schedule_entry('M', [], closed: true),
        schedule_entry('X', [], closed: true),
        schedule_entry('J', [{ 'open' => '19:00', 'close' => '23:30' }]),
        schedule_entry('V', [{ 'open' => '19:00', 'close' => '01:00' }]),
        schedule_entry('S', [{ 'open' => '18:00', 'close' => '01:00' }]),
        schedule_entry('D', [{ 'open' => '18:00', 'close' => '23:00' }])
      ]
    },
    {
      'id' => 'v86',
      'name' => 'Auditori Parc Central',
      'category' => 'concierto',
      'subcategory' => 'acustico',
      'description' => 'Shows mas intimistas, tributos y sesiones acusticas para planes de tarde-noche menos caoticos.',
      'location' => {
        'address' => 'Carrer Rabisancho 15',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.4987, 'longitude' => -0.4304 }
      },
      'favoritesCount' => 876,
      'featured' => false,
      'tags' => ['concierto', 'acustico', 'cultura', 'pareja'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-concierto-86a/900/700',
        'https://picsum.photos/seed/blackcoffee-concierto-86b/900/700',
        'https://picsum.photos/seed/blackcoffee-concierto-86c/900/700'
      ],
      'schedule' => [
        schedule_entry('L', [], closed: true),
        schedule_entry('M', [], closed: true),
        schedule_entry('X', [{ 'open' => '19:00', 'close' => '22:30' }]),
        schedule_entry('J', [{ 'open' => '19:00', 'close' => '22:30' }]),
        schedule_entry('V', [{ 'open' => '19:30', 'close' => '23:30' }]),
        schedule_entry('S', [{ 'open' => '19:30', 'close' => '23:30' }]),
        schedule_entry('D', [{ 'open' => '18:00', 'close' => '21:30' }])
      ]
    },
    {
      'id' => 'v87',
      'name' => 'Paterna Food and Beats',
      'category' => 'festival',
      'subcategory' => 'gastronomico',
      'description' => 'Market callejero, foodtrucks y dj sets al aire libre para una cita larga y muy compartible.',
      'location' => {
        'address' => 'Parc Central de Paterna',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.4983, 'longitude' => -0.4404 }
      },
      'favoritesCount' => 1450,
      'featured' => true,
      'tags' => ['festival', 'foodtrucks', 'dj', 'aire libre'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-festival-87a/900/700',
        'https://picsum.photos/seed/blackcoffee-festival-87b/900/700',
        'https://picsum.photos/seed/blackcoffee-festival-87c/900/700'
      ],
      'schedule' => weekend_schedule('17:00', '01:00', sunday_close: '23:00')
    },
    {
      'id' => 'v88',
      'name' => 'Nitro Sound Weekender',
      'category' => 'festival',
      'subcategory' => 'musical',
      'description' => 'Festival urbano de pequeño formato con varios escenarios y mucho ambiente nocturno.',
      'location' => {
        'address' => 'Avinguda de les Corts Valencianes 60',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.4902, 'longitude' => -0.4167 }
      },
      'favoritesCount' => 1328,
      'featured' => false,
      'tags' => ['festival', 'musica', 'urbano', 'fin de semana'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-festival-88a/900/700',
        'https://picsum.photos/seed/blackcoffee-festival-88b/900/700',
        'https://picsum.photos/seed/blackcoffee-festival-88c/900/700'
      ],
      'schedule' => [
        schedule_entry('L', [], closed: true),
        schedule_entry('M', [], closed: true),
        schedule_entry('X', [], closed: true),
        schedule_entry('J', [], closed: true),
        schedule_entry('V', [{ 'open' => '19:00', 'close' => '02:00' }]),
        schedule_entry('S', [{ 'open' => '17:00', 'close' => '02:00' }]),
        schedule_entry('D', [], closed: true)
      ]
    },
    {
      'id' => 'v89',
      'name' => 'Parc Tecnologic Sunset Fest',
      'category' => 'festival',
      'subcategory' => 'urbano',
      'description' => 'Sesion sunset con stands creativos, musica en vivo y un ambiente muy de tardeo premium.',
      'location' => {
        'address' => 'Carrer Charles Robert Darwin 20',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.5442, 'longitude' => -0.4413 }
      },
      'favoritesCount' => 944,
      'featured' => false,
      'tags' => ['festival', 'sunset', 'market', 'afterwork'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-festival-89a/900/700',
        'https://picsum.photos/seed/blackcoffee-festival-89b/900/700',
        'https://picsum.photos/seed/blackcoffee-festival-89c/900/700'
      ],
      'schedule' => [
        schedule_entry('L', [], closed: true),
        schedule_entry('M', [], closed: true),
        schedule_entry('X', [], closed: true),
        schedule_entry('J', [{ 'open' => '18:30', 'close' => '23:30' }]),
        schedule_entry('V', [{ 'open' => '18:30', 'close' => '00:30' }]),
        schedule_entry('S', [{ 'open' => '18:30', 'close' => '00:30' }]),
        schedule_entry('D', [], closed: true)
      ]
    },
    {
      'id' => 'v90',
      'name' => 'Heron Padel Club',
      'category' => 'deportivo',
      'subcategory' => 'padel',
      'description' => 'Partidas rapidas, zona lounge y ambiente social para un plan activo con pique sano.',
      'location' => {
        'address' => 'Avinguda Francisco Tomas y Valiente 4',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.4898, 'longitude' => -0.4158 }
      },
      'favoritesCount' => 1396,
      'featured' => true,
      'tags' => ['deporte', 'padel', 'social', 'aftermatch'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-deportivo-90a/900/700',
        'https://picsum.photos/seed/blackcoffee-deportivo-90b/900/700',
        'https://picsum.photos/seed/blackcoffee-deportivo-90c/900/700'
      ],
      'schedule' => full_week_schedule('09:00', '23:00')
    },
    {
      'id' => 'v91',
      'name' => 'Ciudad del Rugby Paterna',
      'category' => 'deportivo',
      'subcategory' => 'outdoor',
      'description' => 'Complejo deportivo amplio, perfecto para citas distintas con aire libre y actividad real.',
      'location' => {
        'address' => 'Camino del Barranc d En Dolca s/n',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.5038, 'longitude' => -0.4512 }
      },
      'favoritesCount' => 818,
      'featured' => false,
      'tags' => ['deporte', 'outdoor', 'running', 'equipos'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-deportivo-91a/900/700',
        'https://picsum.photos/seed/blackcoffee-deportivo-91b/900/700',
        'https://picsum.photos/seed/blackcoffee-deportivo-91c/900/700'
      ],
      'schedule' => full_week_schedule('08:00', '22:00')
    },
    {
      'id' => 'v92',
      'name' => 'Vertical Box Park',
      'category' => 'deportivo',
      'subcategory' => 'climbing',
      'description' => 'Escalada indoor, boulder y boxes de entrenamiento para planes activos y nada obvios.',
      'location' => {
        'address' => 'Carrer Ciutat de Barcelona 8',
        'city' => 'Paterna',
        'coordinates' => { 'latitude' => 39.5068, 'longitude' => -0.4362 }
      },
      'favoritesCount' => 1014,
      'featured' => false,
      'tags' => ['deporte', 'climbing', 'indoor', 'reto'],
      'images' => [
        'https://picsum.photos/seed/blackcoffee-deportivo-92a/900/700',
        'https://picsum.photos/seed/blackcoffee-deportivo-92b/900/700',
        'https://picsum.photos/seed/blackcoffee-deportivo-92c/900/700'
      ],
      'schedule' => full_week_schedule('10:00', '22:30')
    }
  ].freeze

  class VenueRecord < ActiveRecord::Base
    self.table_name = 'venues'
    self.primary_key = 'id'
  end

  class VenueSubcategoryRecord < ActiveRecord::Base
    self.table_name = 'venue_subcategories'
    self.primary_key = 'id'
  end

  class VenueImageRecord < ActiveRecord::Base
    self.table_name = 'venue_images'
  end

  class VenueScheduleRecord < ActiveRecord::Base
    self.table_name = 'venue_schedules'
  end

  class UserFavoriteRecord < ActiveRecord::Base
    self.table_name = 'user_favorites'
  end

  def up
    reset_model_information!
    now = Time.current

    migrate_legacy_bars!(now)
    seed_new_venues!(now)
    cleanup_unused_subcategories!([LEGACY_BAR_CATEGORY])
  end

  def down
    reset_model_information!
    now = Time.current

    delete_venues_for_categories!(NEW_ONLY_CATEGORIES)
    rollback_nightlife_categories!(now)
    cleanup_unused_subcategories!(NEW_ONLY_CATEGORIES + NIGHTLIFE_CATEGORIES)
  end

  private

  def reset_model_information!
    [
      VenueRecord,
      VenueSubcategoryRecord,
      VenueImageRecord,
      VenueScheduleRecord,
      UserFavoriteRecord
    ].each(&:reset_column_information)
  end

  def migrate_legacy_bars!(now)
    legacy_bar_venues = VenueRecord.where(category: LEGACY_BAR_CATEGORY).to_a
    return if legacy_bar_venues.empty?

    subcategories_by_id = VenueSubcategoryRecord.where(
      id: legacy_bar_venues.map(&:venue_subcategory_id).compact.uniq
    ).index_by(&:id)

    legacy_bar_venues.each do |venue|
      current_subcategory = subcategories_by_id[venue.venue_subcategory_id]
      override = DISCOTECA_VENUE_OVERRIDES[venue.id]
      target_category = override.present? ? DISCOTECA_CATEGORY : PUB_CATEGORY
      target_subcategory_name = override&.fetch(:subcategory) || current_subcategory&.name
      target_subcategory_id = ensure_subcategory!(target_category, target_subcategory_name, now)

      venue.update_columns(
        category: target_category,
        venue_subcategory_id: target_subcategory_id,
        updated_at: now
      )
    end
  end

  def rollback_nightlife_categories!(now)
    nightlife_venues = VenueRecord.where(category: NIGHTLIFE_CATEGORIES).to_a
    return if nightlife_venues.empty?

    subcategories_by_id = VenueSubcategoryRecord.where(
      id: nightlife_venues.map(&:venue_subcategory_id).compact.uniq
    ).index_by(&:id)

    nightlife_venues.each do |venue|
      current_subcategory = subcategories_by_id[venue.venue_subcategory_id]
      fallback_name = DISCOTECA_TO_BAR_SUBCATEGORY[current_subcategory&.name] || current_subcategory&.name
      fallback_subcategory_id = ensure_subcategory!(LEGACY_BAR_CATEGORY, fallback_name, now)

      venue.update_columns(
        category: LEGACY_BAR_CATEGORY,
        venue_subcategory_id: fallback_subcategory_id,
        updated_at: now
      )
    end
  end

  def seed_new_venues!(now)
    NEW_VENUES.each do |venue_data|
      subcategory_id = ensure_subcategory!(venue_data.fetch('category'), venue_data['subcategory'], now)
      upsert_venue!(venue_data, subcategory_id, now)
      replace_images!(venue_data.fetch('id'), venue_data.fetch('images'), now)
      replace_schedule!(venue_data.fetch('id'), venue_data.fetch('schedule'), now)
    end
  end

  def delete_venues_for_categories!(categories)
    venue_ids = VenueRecord.where(category: categories).pluck(:id)
    return if venue_ids.empty?

    VenueScheduleRecord.where(venue_id: venue_ids).delete_all
    VenueImageRecord.where(venue_id: venue_ids).delete_all
    UserFavoriteRecord.where(venue_id: venue_ids).delete_all
    VenueRecord.where(id: venue_ids).delete_all
  end

  def ensure_subcategory!(category, raw_name, now)
    name = normalize_name(raw_name)
    return nil if name.blank?

    existing = VenueSubcategoryRecord.find_by(category: category, name: name)
    return existing.id if existing

    record = VenueSubcategoryRecord.new(
      id: subcategory_id_for(category, name),
      category: category,
      name: name,
      created_at: now,
      updated_at: now
    )
    record.save!
    record.id
  end

  def upsert_venue!(venue_data, subcategory_id, now)
    location = venue_data.fetch('location')
    coordinates = location.fetch('coordinates')

    venue = VenueRecord.find_or_initialize_by(id: venue_data.fetch('id'))
    venue.assign_attributes(
      name: venue_data.fetch('name'),
      category: venue_data.fetch('category'),
      venue_subcategory_id: subcategory_id,
      description: venue_data.fetch('description'),
      address: location.fetch('address'),
      city: location.fetch('city'),
      latitude: coordinates.fetch('latitude'),
      longitude: coordinates.fetch('longitude'),
      favorites_count: venue_data.fetch('favoritesCount'),
      featured: venue_data.fetch('featured'),
      tags: venue_data.fetch('tags'),
      updated_at: now
    )
    venue.created_at ||= now
    venue.save!
  end

  def replace_images!(venue_id, image_urls, now)
    urls = Array(image_urls).map { |url| url.to_s.strip }.reject(&:blank?).uniq
    raise ActiveRecord::MigrationError, "Venue #{venue_id} does not include image URLs" if urls.empty?

    VenueImageRecord.where(venue_id: venue_id).delete_all
    urls.each_with_index do |url, index|
      VenueImageRecord.create!(
        venue_id: venue_id,
        url: url,
        position: index,
        created_at: now,
        updated_at: now
      )
    end
  end

  def replace_schedule!(venue_id, schedule_entries, now)
    VenueScheduleRecord.where(venue_id: venue_id).delete_all

    Array(schedule_entries).each do |entry|
      slots = Array(entry['slots'])
      closed = entry['closed'] || slots.empty?

      if closed
        VenueScheduleRecord.create!(
          venue_id: venue_id,
          day: entry.fetch('day'),
          closed: true,
          slot_index: 0,
          created_at: now,
          updated_at: now
        )
        next
      end

      slots.each_with_index do |slot, index|
        VenueScheduleRecord.create!(
          venue_id: venue_id,
          day: entry.fetch('day'),
          closed: false,
          slot_open: slot.fetch('open'),
          slot_close: slot.fetch('close'),
          slot_index: index,
          created_at: now,
          updated_at: now
        )
      end
    end
  end

  def cleanup_unused_subcategories!(categories)
    used_subcategory_ids = VenueRecord.where.not(venue_subcategory_id: nil).distinct.pluck(:venue_subcategory_id)
    VenueSubcategoryRecord.where(category: categories).where.not(id: used_subcategory_ids).delete_all
  end

  def normalize_name(value)
    value.to_s.strip.downcase.presence
  end

  def subcategory_id_for(category, name)
    "sub_#{Digest::SHA256.hexdigest("#{category}:#{name}")[0, 12]}"
  end
end
