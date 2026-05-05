class BlackCoffeeVenuesController < ApplicationController
  class InvalidImagePayloadError < StandardError; end
  class InvalidSchedulePayloadError < StandardError; end

  before_action :check_admin
  before_action :set_venue, only: [:show, :edit, :update, :destroy]

  def index
    @title = 'Black Coffee'
    @categories = Venue::CATEGORIES
    @subcategory_options = BlackCoffeeTaxonomy.subcategory_options(params[:category].presence)
    @google_tag_filter = BlackCoffeeTaxonomy.normalize_google_tag(params[:google_tag])
    @google_primary_type_filter = BlackCoffeeTaxonomy.normalize_google_tag(params[:google_primary_type])
    @category_counts = Venue.group(:category).count
    @stats = {
      venues: Venue.count,
      featured: Venue.where(featured: true).count,
      subcategories: BlackCoffeeTaxonomy.subcategory_options.count,
      favorites: UserFavorite.count
    }

    scope = Venue.includes(:venue_subcategory, :venue_images)
    scope = scope.where(category: params[:category]) if params[:category].present? && Venue::CATEGORIES.include?(params[:category])

    normalized_subcategory = Venue.normalize_text(params[:subcategory])
    if normalized_subcategory.present?
      scope = scope.joins(:venue_subcategory)
                   .where('LOWER(venue_subcategories.name) = ?', normalized_subcategory)
    end

    if params[:q].to_s.strip.present?
      query = "%#{params[:q].to_s.strip}%"
      scope = scope.where('venues.name LIKE :query OR venues.city LIKE :query OR venues.address LIKE :query', query: query)
    end

    scope = Venue.filter_by_google_primary_type(scope, @google_primary_type_filter)
    scope = Venue.filter_by_google_tag(scope, @google_tag_filter)

    @venues = Venue.order_by_favorites(scope.order(featured: :desc))
                   .order(updated_at: :desc)
                   .paginate(page: params[:page], per_page: 20)
    @favorite_counts_by_venue_id = Venue.favorite_counts_for(@venues.map(&:id))
  end

  def show
    @title = @venue.name
  end

  def new
    @venue = Venue.new(featured: false)
    @title = 'Nuevo local Black Coffee'
    prepare_form_state
  end

  def edit
    @title = "Editar #{@venue.name}"
    prepare_form_state
  end

  def create
    @venue = Venue.new
    @title = 'Nuevo local Black Coffee'

    if persist_venue
      redirect_to black_coffee_venue_path(@venue), notice: 'Local Black Coffee creado correctamente.'
    else
      prepare_form_state
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @title = "Editar #{@venue.name}"

    if persist_venue
      redirect_to black_coffee_venue_path(@venue), notice: 'Local Black Coffee actualizado correctamente.'
    else
      prepare_form_state
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @venue.destroy
    redirect_to black_coffee_venues_path, notice: 'Local Black Coffee eliminado correctamente.'
  end

  private

  def set_venue
    @venue = Venue.includes(:venue_subcategory, :venue_images, :venue_schedules).find(params[:id])
  end

  def prepare_form_state
    @categories = Venue::CATEGORIES
    @subcategory_options = BlackCoffeeTaxonomy.subcategory_options
    @subcategory_options_json = @subcategory_options.to_json
    @tags_payload = params.dig(:venue, :tags_payload).presence || Array(@venue.tags).to_json
    @image_entries = image_entries_for_form
    @image_order_payload = image_order_payload_for(@image_entries)
    @subcategory_input = params.dig(:venue, :subcategory_name).presence || @venue.subcategory_name
    @schedule_payload = params.dig(:venue, :schedule_payload).presence || @venue.weekly_schedule.to_json
  end

  def persist_venue
    @venue.assign_attributes(venue_params)
    @venue.tags = parse_tags_payload
    image_entries = normalized_image_entries_from_payload
    normalized_schedule = schedule_payload

    if effective_image_entries(image_entries).empty?
      @venue.errors.add(:base, 'Debes indicar al menos una imagen del local')
      return false
    end

    if @venue.category.blank? && subcategory_name.present?
      @venue.errors.add(:category, 'debe estar presente para asignar una subcategoria')
      return false
    end

    ActiveRecord::Base.transaction do
      @venue.assign_subcategory_by_name!(subcategory_name)
      @venue.save!
      @venue.sync_images!(entries: image_entries, uploaded_files_by_key: uploaded_files_by_key)
      @venue.sync_schedule!(normalized_schedule)
    end

    true
  rescue InvalidImagePayloadError
    @venue.errors.add(:base, 'Las imagenes enviadas no tienen un formato valido')
    false
  rescue InvalidSchedulePayloadError
    @venue.errors.add(:base, 'El horario enviado no es valido')
    false
  rescue ActiveRecord::RecordInvalid => e
    return false if e.record == @venue

    @venue.errors.add(:base, e.record.errors.full_messages.to_sentence)
    false
  end

  def venue_params
    params.require(:venue).permit(
      :name,
      :category,
      :description,
      :address,
      :city,
      :postal_code,
      :state,
      :country,
      :country_code,
      :latitude,
      :longitude,
      :google_place_id,
      :featured,
      :internal_test,
      :payment_current,
      :visible
    )
  end

  def subcategory_name
    params.dig(:venue, :subcategory_name)
  end

  def schedule_payload
    raw_payload = params.dig(:venue, :schedule_payload)
    return [] if raw_payload.blank?

    JSON.parse(raw_payload)
  rescue JSON::ParserError
    raise InvalidSchedulePayloadError
  end

  def parse_tags_payload
    raw_payload = params.dig(:venue, :tags_payload)
    return [] if raw_payload.blank?

    Array(JSON.parse(raw_payload)).map do |tag|
      BlackCoffeeTaxonomy.normalize_google_tag(tag)
    end.reject(&:blank?).uniq
  rescue JSON::ParserError
    []
  end

  def image_entries_for_form
    existing_images_by_id = @venue.venue_images.to_a.sort_by(&:position).index_by(&:id)
    entries = normalized_image_entries_from_payload
    return default_image_entries if entries.empty?

    entries.filter_map do |entry|
      case entry[:kind]
      when 'existing'
        image = existing_images_by_id[entry[:id].to_i]
        next unless image

        existing_image_entry(image)
      when 'remote'
        next if entry[:url].blank?

        {
          kind: 'remote',
          url: entry[:url],
          preview_url: entry[:url],
          source_label: 'Link externo'
        }
      when 'upload'
        {
          kind: 'upload',
          upload_key: entry[:upload_key],
          preview_url: nil,
          source_label: 'Archivo manual',
          requires_selection: true
        }
      end
    end
  rescue InvalidImagePayloadError
    default_image_entries
  end

  def default_image_entries
    @venue.venue_images.to_a.sort_by(&:position).map { |image| existing_image_entry(image) }
  end

  def existing_image_entry(image)
    {
      kind: 'existing',
      id: image.id,
      preview_url: image.public_url(base_url: request.base_url),
      source_label: image.external_image? ? 'Link externo' : 'Archivo manual'
    }
  end

  def image_order_payload_for(entries)
    Array(entries).map do |entry|
      case entry[:kind]
      when 'existing'
        { kind: 'existing', id: entry[:id] }
      when 'remote'
        { kind: 'remote', url: entry[:url] }
      when 'upload'
        { kind: 'upload', upload_key: entry[:upload_key] }
      end
    end.compact.to_json
  end

  def normalized_image_entries_from_payload
    raw_payload = params.dig(:venue, :image_order_payload).presence
    return [] if raw_payload.blank?

    Array(JSON.parse(raw_payload)).filter_map do |entry|
      next unless entry.respond_to?(:to_h)

      hash = entry.to_h.with_indifferent_access
      kind = hash[:kind].to_s

      case kind
      when 'existing'
        image_id = hash[:id].to_i
        next if image_id.zero?

        { kind: 'existing', id: image_id }
      when 'remote'
        url = hash[:url].to_s.strip
        next if url.blank?

        { kind: 'remote', url: url }
      when 'upload'
        upload_key = hash[:upload_key].to_s.strip
        next if upload_key.blank?

        { kind: 'upload', upload_key: upload_key }
      end
    end
  rescue JSON::ParserError
    raise InvalidImagePayloadError
  end

  def uploaded_files_by_key
    raw_files = params.dig(:venue, :new_images)
    return {} if raw_files.blank?

    files_hash = raw_files.respond_to?(:to_unsafe_h) ? raw_files.to_unsafe_h : raw_files.to_h
    files_hash.transform_keys(&:to_s).transform_values(&:presence).compact
  end

  def effective_image_entries(entries)
    current_images = @venue.venue_images.to_a.index_by(&:id)
    uploads = uploaded_files_by_key

    Array(entries).filter_map do |entry|
      case entry[:kind]
      when 'existing'
        current_images[entry[:id].to_i]
      when 'remote'
        entry[:url].presence
      when 'upload'
        uploads[entry[:upload_key].to_s]
      end
    end
  end
end
