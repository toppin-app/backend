class BlackCoffeeVenueReviewsController < ApplicationController
  DEFAULT_BATCH_SIZE = 20
  FIXED_BATCH_SIZES = [20, 50, 100, 150, 200].freeze
  MAX_CUSTOM_BATCH_SIZE = 500

  before_action :check_admin
  before_action :hide_content_header, only: [:index, :show]
  before_action :set_batch, only: [:show, :complete, :destroy]

  def index
    @title = 'Revision de locales · Black Coffee'
    @batch_sizes = FIXED_BATCH_SIZES
    @default_batch_size = DEFAULT_BATCH_SIZE
    @category_options = review_category_options
    @review_status_options = review_status_options
    @review_reason_options = Venue::REJECTION_REASON_LABELS.map { |code, label| [label, code] }
    @metrics = review_metrics
    @reason_breakdown = rejection_reason_breakdown
    @review_filter_status = review_status_filter
    @review_filter_reason = review_reason_filter
    @review_filter_category = normalized_review_category(params[:review_category])
    @review_filter_query = params[:review_q].to_s.strip
    @reviewed_venues = reviewed_venues_scope.paginate(page: review_page_param, per_page: 20)
    @favorite_counts_by_venue_id = Venue.favorite_counts_for(@reviewed_venues.map(&:id))
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
    @category_options = review_category_options
  end

  def complete
    result = BlackCoffeeVenueReviewFinalizer.call(
      batch: @batch,
      reviewer: current_user,
      rejections: params[:rejections] || {}
    )

    message = "Lote finalizado: #{result.approved_count} aprobados y #{result.rejected_count} rechazados."
    message += " #{result.corrected_count} locales fueron aprobados corrigiendo su categoria." if result.corrected_count.to_i.positive?

    redirect_to black_coffee_review_path(@batch), notice: message
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
    selected_category = normalized_review_category(params[:category])
    scope = scope.where(category: selected_category) if selected_category.present?

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
    params.permit(:category, :batch_size, :custom_batch_size).to_h.symbolize_keys
  end

  def review_filter_payload(batch_size)
    {
      category: normalized_review_category(params[:category]),
      batch_size: batch_size,
      requested_by_id: current_user&.id,
      requested_at: Time.current.iso8601
    }
  end

  def review_categories
    configured_categories = Venue::CATEGORIES
    google_categories =
      if defined?(GooglePlacesBlackCoffeeClient::CATEGORY_CONFIG)
        GooglePlacesBlackCoffeeClient::CATEGORY_CONFIG.keys
      else
        []
      end
    stored_categories = Venue.where.not(category: [nil, '']).distinct.pluck(:category)

    (configured_categories + google_categories + stored_categories)
      .map { |category| category.to_s.strip }
      .reject(&:blank?)
      .uniq
  end

  def review_category_options
    labels = review_category_labels
    review_categories.map do |category|
      [labels[category] || Venue.category_label_for(category) || category.humanize, category]
    end
  end

  def review_status_options
    [
      ['Todos', 'all'],
      ['Pendientes', Venue::REVIEW_STATUS_PENDING],
      ['Aprobados', Venue::REVIEW_STATUS_APPROVED],
      ['Rechazados', Venue::REVIEW_STATUS_REJECTED]
    ]
  end

  def review_status_filter
    status = params[:review_status].to_s.presence || Venue::REVIEW_STATUS_REJECTED
    return status if status == 'all' || Venue::REVIEW_STATUSES.include?(status)

    Venue::REVIEW_STATUS_REJECTED
  end

  def review_reason_filter
    reason = params[:review_reason].to_s.strip
    return nil unless Venue::REJECTION_REASON_CODES.include?(reason)

    reason
  end

  def review_page_param
    raw_page = params[:review_page].to_s.strip
    return 1 if raw_page.blank?

    [raw_page.to_i, 1].max
  end

  def reviewed_venues_scope
    scope = Venue.includes(
      :venue_subcategory,
      :venue_images,
      :reviewed_by,
      review_batch_items: :review_batch
    )

    scope = scope.where(review_status: @review_filter_status) unless @review_filter_status == 'all'
    scope = scope.where(category: @review_filter_category) if @review_filter_category.present?
    scope = scope.where(review_rejection_reason: @review_filter_reason) if @review_filter_reason.present?

    if @review_filter_query.present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(@review_filter_query)}%"
      scope = scope.where(
        'venues.name LIKE :query OR venues.city LIKE :query OR venues.address LIKE :query OR venues.state LIKE :query OR venues.google_place_id LIKE :query',
        query: query
      )
    end

    scope.order(Arel.sql('CASE WHEN venues.reviewed_at IS NULL THEN 1 ELSE 0 END'))
         .order(reviewed_at: :desc, updated_at: :desc, id: :desc)
  end

  def review_category_labels
    labels = Venue::CATEGORY_LABELS.dup

    return labels unless defined?(GooglePlacesBlackCoffeeClient::CATEGORY_CONFIG)

    GooglePlacesBlackCoffeeClient::CATEGORY_CONFIG.each_with_object(labels) do |(category, config), memo|
      memo[category.to_s] = config[:label] if config[:label].present?
    end
  end

  def normalized_review_category(value)
    category = Venue.normalize_category(value)
    Venue::CATEGORIES.include?(category) ? category : nil
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
