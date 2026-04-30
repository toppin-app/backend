class BlackCoffeeBulkImportsController < ApplicationController
  before_action :check_admin
  before_action :set_bulk_import, only: [:show, :status, :advance, :retry]

  def create
    region = BlackCoffeeImportRegion.find(params[:region_id])
    existing_import = region.bulk_imports.active.recent_first.first
    failed_import = region.bulk_imports.where(status: 'failed').recent_first.first

    if existing_import.present?
      redirect_to black_coffee_bulk_import_path(existing_import), notice: "Ya hay una importacion total activa para #{region.name}. Seguimos desde ahi."
      return
    end

    if failed_import&.retryable?
      redirect_to black_coffee_bulk_import_path(failed_import), alert: "Hay una importacion total fallida para #{region.name}. Reintenta ese intento para no duplicar candidatos."
      return
    end

    bulk_import = BlackCoffeeBulkImportRunner.start!(region: region)
    redirect_to black_coffee_bulk_import_path(bulk_import), notice: "Importacion total preparada para #{region.name}. Iremos avanzando por celdas para evitar timeouts."
  rescue ActiveRecord::RecordNotFound
    redirect_to black_coffee_google_imports_path, alert: 'No se encontro la comunidad solicitada.'
  rescue StandardError => e
    redirect_to black_coffee_google_imports_path(anchor: "region-#{params[:region_id]}"), alert: "No se pudo preparar la importacion total: #{e.message}"
  end

  def show
    @title = "Importacion total #{@bulk_import.black_coffee_import_region.name}"
    @progress_payload = @bulk_import.as_progress_json
  end

  def status
    render json: @bulk_import.as_progress_json
  end

  def advance
    BlackCoffeeBulkImportRunner.advance!(bulk_import: @bulk_import)
    render json: @bulk_import.reload.as_progress_json
  rescue StandardError => e
    render json: @bulk_import.reload.as_progress_json.merge(errorMessage: e.message), status: :unprocessable_entity
  end

  def retry
    unless @bulk_import.retryable?
      redirect_to black_coffee_bulk_import_path(@bulk_import), alert: 'Esta importacion no tiene celdas fallidas pendientes de reintento.'
      return
    end

    BlackCoffeeBulkImportRunner.retry_failed!(bulk_import: @bulk_import)
    redirect_to black_coffee_bulk_import_path(@bulk_import), notice: 'Reintentaremos solo las celdas que fallaron. Lo ya guardado se conserva.'
  rescue StandardError => e
    redirect_to black_coffee_bulk_import_path(@bulk_import), alert: "No se pudo reintentar la importacion: #{e.message}"
  end

  private

  def set_bulk_import
    @bulk_import = BlackCoffeeBulkImport.includes(
      :black_coffee_import_region,
      :import_runs,
      :import_steps
    ).find(params[:id])
  end
end
