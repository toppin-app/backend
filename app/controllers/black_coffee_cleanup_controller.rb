class BlackCoffeeCleanupController < ApplicationController
  DELETE_CONFIRMATION_TEXT = 'BORRAR'.freeze
  REJECT_CONFIRMATION_TEXT = 'RECHAZAR'.freeze

  before_action :check_admin
  before_action :hide_content_header

  def show
    @title = 'Limpieza Black Coffee'
    prepare_cleanup
  end

  def create
    prepare_cleanup

    unless params[:confirm_text].to_s == @confirmation_text
      flash.now[:alert] = "Escribe #{@confirmation_text} para confirmar esta accion masiva."
      render :show, status: :unprocessable_entity
      return
    end

    result = @cleanup.reject_operation? ? @cleanup.reject!(reviewed_by: current_user) : @cleanup.delete!
    message = cleanup_success_message(result)

    redirect_to black_coffee_cleanup_path(cleanup_params.to_h), notice: message
  rescue StandardError => e
    flash.now[:alert] = "No se pudo completar la accion masiva: #{e.message}"
    render :show, status: :unprocessable_entity
  end

  private

  def prepare_cleanup
    @categories = Venue::CATEGORIES
    @operation_options = BlackCoffeeVenueCleanup::OPERATION_OPTIONS
    @source_options = BlackCoffeeVenueCleanup::SOURCE_OPTIONS
    @visibility_options = BlackCoffeeVenueCleanup::VISIBILITY_OPTIONS
    @cleanup = BlackCoffeeVenueCleanup.new(cleanup_params)
    @confirmation_text = confirmation_text_for(@cleanup.operation)
    @rejection_reason_options = Venue::REJECTION_REASON_LABELS.map { |code, label| [label, code] }
    @preview = @cleanup.preview
  end

  def cleanup_params
    params.permit(
      :operation,
      :category,
      :source,
      :visibility,
      :google_tag,
      :google_primary_type,
      :review_rejection_reason,
      :review_rejection_note
    )
  end

  def confirmation_text_for(operation)
    operation == BlackCoffeeVenueCleanup::OPERATION_REJECT ? REJECT_CONFIRMATION_TEXT : DELETE_CONFIRMATION_TEXT
  end

  def cleanup_success_message(result)
    if @cleanup.reject_operation?
      reason = Venue.rejection_reason_label(result[:review_rejection_reason])
      message = "Revision masiva completada: #{result[:rejected_count]} locales marcados como rechazados"
      message += " con motivo \"#{reason}\"." if reason.present?
      return message
    end

    message = "Limpieza completada: #{result[:deleted_count]} locales borrados."
    if result[:reset_candidate_count].to_i.positive?
      message += " Se reactivaron #{result[:reset_candidate_count]} candidatos del importador."
    end
    message
  end
end
