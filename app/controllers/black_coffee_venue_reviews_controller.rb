class BlackCoffeeVenueReviewsController < ApplicationController
  DEFAULT_BATCH_SIZE = 20
  FIXED_BATCH_SIZES = [20, 50, 100, 150, 200].freeze
  MAX_CUSTOM_BATCH_SIZE = 500

  before_action :check_admin
  before_action :set_batch, only: [:show, :complete, :destroy]

  def index
    @title = 'Revision de locales · Black Coffee'
    @batch_sizes = FIXED_BATCH_SIZES
    @default_batch_size = DEFAULT_BATCH_SIZE
    @categories = review_categories
    @subcategory_options = review_subcategory_options
    @metrics = review_metrics
    @reason_breakdown = rejection_reason_breakdown
    @open_batches = review_batches_available? ? BlackCoffeeReviewBatch.open.recent_first.limit(5) : []
    @recent_batches = review_batches_available? ? BlackCoffeeReviewBatch.includes(:reviewed_by).recent_first.limit(20) : []
  end

  def create
    batch_size = parsed_batch_size
    venues = pending_scope.limit(batch_size).to_a

    if venues.empty?
      redirect_to black_coffee_reviews_path(review_filter_params), alert: 'No hay locales pendientes que coincidan con estos filtros.'
      return
    end

    batch = nil
    BlackCoffeeReviewBatch.transaction do
      now = Time.current
      batch = BlackCoffeeReviewBatch.create!(
        status: 'open',
        filters_payload: review_filter_payload(batch_size),
        batch_size: batch_size,
        total_places: venues.size
      )

      BlackCoffeeReviewBatchItem.insert_all!(
        venues.map do |venue|
          {
            black_coffee_review_batch_id: batch.id,
            venue_id: venue.id,
            review_status: Venue::REVIEW_STATUS_PENDING,
            created_at: now,
            updated_at: now
          }
        end
      )
    end

    redirect_to black_coffee_review_path(batch), notice: "Lote preparado con #{venues.size} locales pendientes."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid, ArgumentError => e
    redirect_to black_coffee_reviews_path(review_filter_params), alert: "No se pudo crear el lote: #{e.message}"
  end

  def show
    @title = "Revision Black Coffee ##{@batch.id}"
    @items = @batch.review_items.includes(venue: [:venue_subcategory, :venue_images]).ordered
    @reason_labels = Venue::REJECTION_REASON_LABELS
  end

  def complete
    result = BlackCoffeeVenueReviewFinalizer.call(
      batch: @batch,
      reviewer: current_user,
      rejections: params[:rejections] || {}
    )

    redirect_to black_coffee_review_path(@batch),
                notice: "Lote finalizado: #{result.approved_count} aprobados y #{result.rejected_count} rechazados."
  rescue ArgumentError, ActiveRecord::ActiveRecordError => e
    redirect_to black_coffee_review_path(@batch), alert: "No se pudo finalizar el lote: #{e.message}"
  end

  def destroy
    result = BlackCoffeeVenueReviewBatchReverter.call(batch: @batch)
    redirect_to black_coffee_reviews_path,
                notice: "Lote eliminado. #{result.total_places} locales volvieron a pendiente; se deshicieron #{result.approved_count} aprobaciones y #{result.rejected_count} rechazos."
  rescue ActiveRecord::ActiveRecordError => e
    redirect_back fallback_location: black_coffee_reviews_path, alert: "No se pudo eliminar el lote: #{e.message}"
  end

  private

  def set_batch
    @batch = BlackCoffeeReviewBatch.find(params[:id])
  end

  def pending_scope
    scope = Venue.includes(:venue_subcategory, :venue_images)
                 .where(review_status: Venue::REVIEW_STATUS_PENDING)
                 .order(created_at: :asc, id: :asc)
    if review_batches_available?
      open_batch_venue_ids = BlackCoffeeReviewBatchItem
                             .joins(:review_batch)
                             .where(black_coffee_review_batches: { status: 'open' })
                             .select(:venue_id)
      scope = scope.where.not(id: open_batch_venue_ids)
    end
    scope = scope.where(category: params[:category]) if params[:category].present?

    normalized_subcategory = Venue.normalize_text(params[:subcategory])
    if normalized_subcategory.present?
      scope = scope.joins(:venue_subcategory)
                   .where('LOWER(venue_subcategories.name) = ?', normalized_subcategory)
    end

    scope
  end

  def parsed_batch_size
    selected_size = params[:batch_size].to_s
    value =
      if selected_size == 'custom'
        params[:custom_batch_size].to_i
      else
        selected_size.to_i
      end

    value = DEFAULT_BATCH_SIZE unless value.positive?
    [[value, 1].max, MAX_CUSTOM_BATCH_SIZE].min
  end

  def review_filter_params
    params.permit(:category, :subcategory, :batch_size, :custom_batch_size).to_h.symbolize_keys
  end

  def review_filter_payload(batch_size)
    {
      category: params[:category].presence,
      subcategory: params[:subcategory].presence,
      batch_size: batch_size,
      requested_by_id: current_user&.id,
      requested_at: Time.current.iso8601
    }
  end

  def review_categories
    categories = Venue.where.not(category: [nil, '']).distinct.order(:category).pluck(:category)
    categories.presence || Venue::CATEGORIES
  end

  def review_subcategory_options
    if ActiveRecord::Base.connection.data_source_exists?('venue_subcategories')
      VenueSubcategory.order(:category, :name).map do |subcategory|
        {
          category: subcategory.category,
          name: subcategory.name,
          label: BlackCoffeeTaxonomy.label_for(subcategory.category, subcategory.name)
        }
      end
    else
      BlackCoffeeTaxonomy.subcategory_options
    end
  end

  def review_metrics
    total = Venue.count
    counts = Venue.group(:review_status).count
    pending = counts[Venue::REVIEW_STATUS_PENDING].to_i
    approved = counts[Venue::REVIEW_STATUS_APPROVED].to_i
    rejected = counts[Venue::REVIEW_STATUS_REJECTED].to_i
    reviewed = approved + rejected

    {
      total: total,
      pending: pending,
      approved: approved,
      rejected: rejected,
      reviewed: reviewed,
      reviewed_percentage: total.positive? ? ((reviewed.to_f / total) * 100).round(1) : 0
    }
  end

  def rejection_reason_breakdown
    Venue.where(review_status: Venue::REVIEW_STATUS_REJECTED)
         .group(:review_rejection_reason)
         .count
  end

  def review_batches_available?
    ActiveRecord::Base.connection.data_source_exists?('black_coffee_review_batches')
  end
end
