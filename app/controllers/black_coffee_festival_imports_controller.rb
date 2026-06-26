class BlackCoffeeFestivalImportsController < ApplicationController
  MAX_PAGES = FanMusicFest::Importer::MAX_PAGES
  MAX_DETAILS = 500
  MIN_REQUEST_DELAY_SECONDS = FanMusicFest::Client::DEFAULT_CRAWL_DELAY_SECONDS
  MAX_REQUEST_DELAY_SECONDS = 120

  before_action :check_admin
  before_action :hide_content_header
  before_action :set_run, only: [:show, :cancel]

  def index
    @title = 'Importador FanMusicFest'
    @recent_runs = BlackCoffeeFestivalImportRun.includes(:created_by).recent_first.limit(20)
    @latest_run = @recent_runs.first
  end

  def create
    run = FanMusicFest::Importer.enqueue!(
      created_by: current_user,
      attributes: run_attributes
    )
    redirect_to black_coffee_festival_import_path(run),
                notice: 'Importacion FanMusicFest creada. Se ejecuta en servidor respetando robots.txt y sin descargar imagenes.'
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_festival_imports_path, alert: "No se pudo crear la importacion: #{e.message}"
  end

  def show
    @title = "Importacion FanMusicFest ##{@run.id}"
    @status_counts = @run.items.group(:status).count
    @items = @run.items.ordered.paginate(page: params[:page], per_page: 50)
  end

  def cancel
    if @run.finished?
      redirect_to black_coffee_festival_import_path(@run), alert: 'Esta importacion ya esta finalizada.'
      return
    end

    @run.update!(status: 'cancelled', completed_at: Time.current)
    redirect_to black_coffee_festival_import_path(@run), notice: 'Importacion cancelada. No se crean mas locales.'
  rescue ActiveRecord::ActiveRecordError => e
    redirect_to black_coffee_festival_import_path(@run), alert: "No se pudo cancelar la importacion: #{e.message}"
  end

  private

  def set_run
    @run = BlackCoffeeFestivalImportRun.find(params[:id])
  end

  def run_attributes
    return import_all_attributes if params[:preset].to_s == 'import_all_spain'

    mode = params[:mode].to_s == 'import' ? 'import' : 'dry_run'
    operation = params[:operation].to_s == 'refresh_details' ? 'refresh_details' : 'import'
    max_details_default = operation == 'refresh_details' ? 100 : 0
    {
      mode: mode,
      operation: operation,
      status: 'pending',
      max_pages: clamped_integer(params[:max_pages], default: 1, min: 1, max: MAX_PAGES),
      max_details: clamped_integer(params[:max_details], default: max_details_default, min: 0, max: MAX_DETAILS),
      request_delay_seconds: clamped_decimal(params[:request_delay_seconds], default: MIN_REQUEST_DELAY_SECONDS, min: MIN_REQUEST_DELAY_SECONDS, max: MAX_REQUEST_DELAY_SECONDS),
      strict_country_code: 'ES',
      import_details: boolean_param(params[:import_details]),
      download_images: boolean_param(params[:download_images], default: true),
      only_future: boolean_param(params[:only_future], default: true),
      auto_publish: operation == 'import' && mode == 'import' && boolean_param(params[:auto_publish]),
      preserve_manual_edits: true
    }
  end

  # One-click "bring every Spanish festival at once": walks every calendar page,
  # keeps only future Spanish festivals, enriches every detail page and downloads
  # each image as a binary asset. Festivals are created visible but pending review.
  #
  # This runs as a background job and, because every request honours the >=10s
  # crawl delay, can take from several minutes up to ~1 hour. It is safe to cancel
  # and re-run: already-imported festivals are detected as duplicates and skipped.
  def import_all_attributes
    {
      mode: 'import',
      operation: 'import',
      status: 'pending',
      max_pages: MAX_PAGES,
      max_details: MAX_DETAILS,
      request_delay_seconds: clamped_decimal(params[:request_delay_seconds], default: MIN_REQUEST_DELAY_SECONDS, min: MIN_REQUEST_DELAY_SECONDS, max: MAX_REQUEST_DELAY_SECONDS),
      strict_country_code: 'ES',
      import_details: true,
      download_images: true,
      only_future: true,
      auto_publish: false,
      preserve_manual_edits: true
    }
  end

  # ActiveModel's boolean cast returns nil for a missing/blank checkbox, which would
  # violate the NOT NULL constraint on these columns. Coerce to a real boolean.
  def boolean_param(value, default: false)
    return default if value.nil?

    ActiveModel::Type::Boolean.new.cast(value) ? true : false
  end

  def clamped_integer(value, default:, min:, max:)
    parsed = value.to_s.strip.presence&.to_i || default
    [[parsed, min].max, max].min
  end

  def clamped_decimal(value, default:, min:, max:)
    parsed = BigDecimal(value.to_s.strip.presence || default.to_s)
    [[parsed, BigDecimal(min.to_s)].max, BigDecimal(max.to_s)].min
  rescue ArgumentError
    default
  end
end
