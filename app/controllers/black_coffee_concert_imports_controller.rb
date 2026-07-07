class BlackCoffeeConcertImportsController < ApplicationController
  MAX_PAGES_PER_SOURCE = SongkickConcerts::Importer::MAX_PAGES_PER_SOURCE
  MAX_EVENTS = SongkickConcerts::Importer::MAX_EVENTS
  MIN_REQUEST_DELAY_SECONDS = SongkickConcerts::Client::DEFAULT_CRAWL_DELAY_SECONDS
  MAX_REQUEST_DELAY_SECONDS = 120

  before_action :check_admin
  before_action :hide_content_header
  before_action :set_run, only: [:show, :cancel]

  def index
    @title = 'Importador Songkick'
    @recent_runs = BlackCoffeeConcertImportRun.includes(:created_by).recent_first.limit(20)
    @default_source_paths = SongkickConcerts::Importer::DEFAULT_SOURCE_PATHS_TEXT
  end

  def create
    run = SongkickConcerts::Importer.enqueue!(
      created_by: current_user,
      attributes: run_attributes
    )
    redirect_to black_coffee_concert_import_path(run),
                notice: 'Importacion Songkick creada. Se ejecuta en servidor respetando robots.txt y sin consultar fichas de detalle.'
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_concert_imports_path, alert: "No se pudo crear la importacion: #{e.message}"
  end

  def show
    @title = "Importacion Songkick ##{@run.id}"
    @status_counts = @run.items.group(:status).count
    @items = @run.items.ordered.paginate(page: params[:page], per_page: 50)
  end

  def cancel
    if @run.finished?
      redirect_to black_coffee_concert_import_path(@run), alert: 'Esta importacion ya esta finalizada.'
      return
    end

    @run.update!(status: 'cancelled', completed_at: Time.current)
    redirect_to black_coffee_concert_import_path(@run), notice: 'Importacion cancelada. No se crean mas conciertos.'
  rescue ActiveRecord::ActiveRecordError => e
    redirect_to black_coffee_concert_import_path(@run), alert: "No se pudo cancelar la importacion: #{e.message}"
  end

  private

  def set_run
    @run = BlackCoffeeConcertImportRun.find(params[:id])
  end

  def run_attributes
    return import_all_attributes if params[:preset].to_s == 'import_all_spain'

    {
      mode: params[:mode].to_s == 'import' ? 'import' : 'dry_run',
      status: 'pending',
      source_paths: source_paths_param,
      max_pages_per_source: clamped_integer(params[:max_pages_per_source], default: 1, min: 1, max: MAX_PAGES_PER_SOURCE),
      max_events: clamped_integer(params[:max_events], default: 500, min: 1, max: MAX_EVENTS),
      request_delay_seconds: clamped_decimal(params[:request_delay_seconds], default: MIN_REQUEST_DELAY_SECONDS, min: MIN_REQUEST_DELAY_SECONDS, max: MAX_REQUEST_DELAY_SECONDS),
      strict_country_code: 'ES',
      include_festivals: boolean_param(params[:include_festivals]),
      download_images: boolean_param(params[:download_images], default: true),
      only_future: boolean_param(params[:only_future], default: true),
      auto_publish: params[:mode].to_s == 'import' && boolean_param(params[:auto_publish]),
      preserve_manual_edits: true
    }
  end

  # One-click Spain import: walks configured Songkick metro pages and creates
  # future Spanish concerts as visible venues pending review. This intentionally
  # avoids individual detail pages to keep requests low and predictable.
  def import_all_attributes
    {
      mode: 'import',
      status: 'pending',
      source_paths: SongkickConcerts::Importer::DEFAULT_SOURCE_PATHS_TEXT,
      max_pages_per_source: clamped_integer(params[:max_pages_per_source], default: 10, min: 1, max: MAX_PAGES_PER_SOURCE),
      max_events: clamped_integer(params[:max_events], default: MAX_EVENTS, min: 1, max: MAX_EVENTS),
      request_delay_seconds: clamped_decimal(params[:request_delay_seconds], default: MIN_REQUEST_DELAY_SECONDS, min: MIN_REQUEST_DELAY_SECONDS, max: MAX_REQUEST_DELAY_SECONDS),
      strict_country_code: 'ES',
      include_festivals: false,
      download_images: true,
      only_future: true,
      auto_publish: false,
      preserve_manual_edits: true
    }
  end

  def source_paths_param
    raw_paths = params[:source_paths].to_s.lines.map(&:strip).reject(&:blank?)
    paths = raw_paths.presence || SongkickConcerts::Importer::DEFAULT_SOURCE_PATHS
    paths.join("\n")
  end

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
