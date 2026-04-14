class BlackCoffeeVenuesController < ApplicationController
  before_action :check_admin
  before_action :set_venue, only: [:show, :edit, :update, :destroy]

  def index
    @title = 'Black Coffee'
    @categories = Venue::CATEGORIES
    @category_counts = Venue.group(:category).count
    @stats = {
      venues: Venue.count,
      featured: Venue.where(featured: true).count,
      subcategories: VenueSubcategory.count,
      favorites: Venue.sum(:favorites_count)
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

    @venues = scope.order(featured: :desc, favorites_count: :desc, updated_at: :desc)
                   .paginate(page: params[:page], per_page: 20)
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
    @subcategory_options = VenueSubcategory.order(:category, :name)
    @subcategory_options_json = @subcategory_options.map { |subcategory| { name: subcategory.name, category: subcategory.category } }.to_json
    @tag_list_input = params.dig(:venue, :tag_list).presence || Array(@venue.tags).join(', ')
    @existing_images = @venue.venue_images.to_a.sort_by(&:position)
    @kept_existing_image_ids =
      if params.dig(:venue, :existing_image_ids).nil?
        @existing_images.map(&:id)
      else
        Array(params.dig(:venue, :existing_image_ids)).map(&:to_i)
      end
    @subcategory_input = params.dig(:venue, :subcategory_name).presence || @venue.subcategory_name
    @schedule_payload = params.dig(:venue, :schedule_payload).presence || @venue.weekly_schedule.to_json
  end

  def persist_venue
    @venue.assign_attributes(venue_params)
    @venue.tags = parse_tag_list

    if persisted_image_ids.empty? && new_images.empty?
      @venue.errors.add(:base, 'Debes subir al menos una imagen del local')
      return false
    end

    if @venue.category.blank? && subcategory_name.present?
      @venue.errors.add(:category, 'debe estar presente para asignar una subcategoria')
      return false
    end

    ActiveRecord::Base.transaction do
      @venue.assign_subcategory_by_name!(subcategory_name)
      @venue.save!
      @venue.sync_images!(existing_image_ids: persisted_image_ids, new_files: new_images)
      @venue.sync_schedule!(schedule_payload)
    end

    true
  rescue JSON::ParserError
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
      :latitude,
      :longitude,
      :featured
    )
  end

  def subcategory_name
    params.dig(:venue, :subcategory_name)
  end

  def persisted_image_ids
    return [] unless @venue.persisted?

    requested_ids = Array(params.dig(:venue, :existing_image_ids)).reject(&:blank?).map(&:to_i)
    @venue.venue_images.where(id: requested_ids).pluck(:id)
  end

  def new_images
    Array(params.dig(:venue, :new_images)).reject(&:blank?)
  end

  def schedule_payload
    raw_payload = params.dig(:venue, :schedule_payload)
    return [] if raw_payload.blank?

    JSON.parse(raw_payload)
  end

  def parse_tag_list
    params.dig(:venue, :tag_list).to_s.split(',').map(&:strip).reject(&:blank?).uniq
  end
end
