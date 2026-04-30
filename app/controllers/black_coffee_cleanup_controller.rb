class BlackCoffeeCleanupController < ApplicationController
  CONFIRMATION_TEXT = 'BORRAR'.freeze

  before_action :check_admin

  def show
    @title = 'Limpieza Black Coffee'
    prepare_cleanup
  end

  def create
    prepare_cleanup

    unless params[:confirm_text].to_s == CONFIRMATION_TEXT
      flash.now[:alert] = "Escribe #{CONFIRMATION_TEXT} para confirmar la limpieza masiva."
      render :show, status: :unprocessable_entity
      return
    end

    result = @cleanup.delete!
    message = "Limpieza completada: #{result[:deleted_count]} locales borrados."
    if result[:reset_candidate_count].to_i.positive?
      message += " Se reactivaron #{result[:reset_candidate_count]} candidatos del importador."
    end

    redirect_to black_coffee_cleanup_path(cleanup_params.to_h), notice: message
  rescue StandardError => e
    flash.now[:alert] = "No se pudo completar la limpieza: #{e.message}"
    render :show, status: :unprocessable_entity
  end

  private

  def prepare_cleanup
    @categories = Venue::CATEGORIES
    @source_options = BlackCoffeeVenueCleanup::SOURCE_OPTIONS
    @visibility_options = BlackCoffeeVenueCleanup::VISIBILITY_OPTIONS
    @confirmation_text = CONFIRMATION_TEXT
    @cleanup = BlackCoffeeVenueCleanup.new(cleanup_params)
    @preview = @cleanup.preview
  end

  def cleanup_params
    params.permit(:category, :source, :visibility)
  end
end
