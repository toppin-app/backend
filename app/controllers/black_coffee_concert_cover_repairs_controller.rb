class BlackCoffeeConcertCoverRepairsController < ApplicationController
  before_action :check_admin
  before_action :hide_content_header
  before_action :set_batch, only: [:show, :status, :cancel]

  def index
    @title = 'Portadas de conciertos'
    @recent_batches = BlackCoffeeConcertCoverRepairBatch.includes(:created_by).recent_first.limit(30)
    @cover_inventory = {
      approved: BlackCoffeeConcertCoverRepairRunner.cover_inventory(review_status_filter: 'approved'),
      pending: BlackCoffeeConcertCoverRepairRunner.cover_inventory(review_status_filter: 'pending')
    }
  end

  def create
    batch = BlackCoffeeConcertCoverRepairRunner.create_batch!(
      created_by: current_user,
      review_status_filter: params[:review_status_filter].presence || 'approved'
    )
    token = SecureRandom.hex(16)
    batch.update!(worker_token: token)
    BlackCoffeeConcertCoverRepairJob.perform_later(batch.id, process_limit, token)

    redirect_to black_coffee_concert_cover_repair_path(batch),
                notice: "Proceso creado para #{batch.total_venues} conciertos sin portada binaria interna. Las URLs existentes se descargaran y reemplazaran. Continuara en el servidor aunque cierres la pantalla."
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to black_coffee_concert_cover_repairs_path, alert: "No se pudo crear el proceso: #{e.message}"
  end

  def show
    @title = "Portadas de conciertos ##{@batch.id}"
    prepare_batch_state
  end

  def status
    prepare_batch_state
    response.headers['Cache-Control'] = 'no-store'
    render partial: 'live_status', layout: false
  end

  def cancel
    if @batch.finished?
      redirect_to black_coffee_concert_cover_repair_path(@batch), alert: 'Este proceso ya esta finalizado.'
      return
    end

    @batch.update!(status: 'cancelled', completed_at: Time.current, worker_token: nil)
    redirect_to black_coffee_concert_cover_repair_path(@batch),
                notice: 'Proceso cancelado. Las portadas ya recuperadas y los cambios a pendiente de revisión se conservan.'
  rescue ActiveRecord::ActiveRecordError => e
    redirect_to black_coffee_concert_cover_repair_path(@batch), alert: "No se pudo cancelar el proceso: #{e.message}"
  end

  private

  def set_batch
    @batch = BlackCoffeeConcertCoverRepairBatch.find(params[:id])
  end

  def process_limit
    raw = params[:limit].presence || BlackCoffeeConcertCoverRepairRunner::DEFAULT_LIMIT
    [[raw.to_i, 1].max, BlackCoffeeConcertCoverRepairRunner::MAX_LIMIT].min
  end

  def prepare_batch_state
    @batch.reload
    @outcome_counts = @batch.items.group(:status).count
    @items = @batch.items.includes(:venue).recent_first.paginate(page: params[:page], per_page: 50)
  end

end
