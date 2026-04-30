class BlackCoffeeBulkImportsController < ApplicationController
  before_action :check_admin
  before_action :set_bulk_import, only: [:show, :status, :advance]

  def create
    region = BlackCoffeeImportRegion.find(params[:region_id])
    existing_import = region.bulk_imports.active.recent_first.first

    if existing_import.present?
      redirect_to black_coffee_bulk_import_path(existing_import), notice: "Ya hay una importacion total activa para #{region.name}. Seguimos desde ahi."
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

  private

  def set_bulk_import
    @bulk_import = BlackCoffeeBulkImport.includes(
      :black_coffee_import_region,
      :import_runs,
      :import_steps
    ).find(params[:id])
  end
end
