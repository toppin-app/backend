class BlackCoffeeVenueReclassificationsController < ApplicationController
  before_action :check_admin
  before_action :hide_content_header

  def show
    @title = 'Reclasificacion masiva de locales'
    prepare_reclassification
  end

  def create
    @title = 'Reclasificacion masiva de locales'
    @reclassifier = BlackCoffeeVenueReclassifier.new(filter_params)
    result = @reclassifier.reclassify!(
      target_category: params[:target_category],
      selection_mode: params[:selection_mode],
      selected_ids: params[:venue_ids],
      confirmation_text: params[:confirm_text],
      changed_by: current_user
    )

    redirect_to black_coffee_venue_reclassification_path(filter_params.to_h),
                notice: reclassification_success_message(result)
  rescue StandardError => e
    flash.now[:alert] = "No se pudo completar la reclasificacion masiva: #{e.message}"
    prepare_reclassification
    render :show, status: :unprocessable_entity
  end

  private

  def prepare_reclassification
    @categories = Venue::CATEGORIES
    @selection_options = BlackCoffeeVenueReclassifier::SELECTION_OPTIONS
    @confirmation_text = BlackCoffeeVenueReclassifier::CONFIRMATION_TEXT
    @reclassifier ||= BlackCoffeeVenueReclassifier.new(filter_params)
    @preview = @reclassifier.preview
    @venues = @reclassifier.scope
                             .includes(:venue_subcategory)
                             .order(updated_at: :desc)
                             .paginate(page: params[:page], per_page: 30)
  end

  def filter_params
    params.permit(
      :name_query,
      :city,
      :state,
      :country,
      :google_primary_type,
      :google_tag,
      categories: []
    )
  end

  def reclassification_success_message(result)
    message = "Reclasificacion completada: #{result[:changed_count]} locales pasaron a #{result[:new_category]}."
    if result[:unchanged_count].positive?
      message += " #{result[:unchanged_count]} ya estaban en esa categoria y no se modificaron."
    end
    message
  end
end
