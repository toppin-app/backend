require 'net/http'
require 'uri'

class BlackCoffeePendingImageAuditRunner
  DEFAULT_LIMIT = 100
  MAX_LIMIT = 500
  INSERT_BATCH_SIZE = 1_000
  IMAGE_REJECTION_REASON = 'bad_photos'.freeze

  CheckResult = Struct.new(:status, :error_type, :http_status, :error_message, keyword_init: true)

  def self.create_batch!(base_url:)
    new(base_url: base_url).create_batch!
  end

  def self.advance!(batch:, limit: DEFAULT_LIMIT)
    new(batch: batch, limit: limit).advance!
  end

  def self.reject_failed!(batch:, reviewer:)
    new(batch: batch).reject_failed!(reviewer: reviewer)
  end

  def initialize(batch: nil, base_url: nil, limit: DEFAULT_LIMIT, checker: nil)
    @batch = batch
    @base_url = base_url
    @limit = [[limit.to_i, 1].max, MAX_LIMIT].min
    @checker = checker || ImageChecker.new
  end

  def create_batch!
    batch = nil

    BlackCoffeeImageAuditBatch.transaction do
      pending_venues = Venue
                       .includes(:venue_images)
                       .where(review_status: Venue::REVIEW_STATUS_PENDING)
                       .order(:id)
      batch = BlackCoffeeImageAuditBatch.create!(
        status: 'pending',
        total_venues: pending_venues.count,
        report_payload: {}
      )

      now = Time.current
      rows = []

      pending_venues.find_each do |venue|
        images = venue.venue_images.to_a.sort_by(&:position)
        if images.empty?
          rows << item_row(
            batch: batch,
            venue: venue,
            status: 'failed',
            error_type: 'missing_image',
            error_message: 'El local no tiene imagenes guardadas.',
            checked_at: now
          )
          flush_rows!(rows)
          next
        end

        images.each do |image|
          rows << item_row(
            batch: batch,
            venue: venue,
            venue_image: image,
            image_url: image.public_url(base_url: base_url),
            status: 'pending'
          )
          flush_rows!(rows)
        end
      end

      flush_rows!(rows, force: true)
      refresh_counts!(batch)
    end

    batch
  end

  def advance!
    raise ArgumentError, 'No hay auditoria de imagenes.' unless batch
    return refresh_counts!(batch) if batch.finished?

    batch.update!(status: 'running', started_at: batch.started_at || Time.current)
    items = batch.items.pending.ordered.limit(limit).to_a

    items.each do |item|
      result = checker.check(item.image_url)
      item.update_columns(
        status: result.status,
        error_type: result.error_type,
        http_status: result.http_status,
        error_message: result.error_message,
        checked_at: Time.current,
        updated_at: Time.current
      )
    end

    refresh_counts!(batch)
  rescue StandardError => e
    batch&.update_columns(status: 'failed', error_message: e.message, updated_at: Time.current)
    raise
  end

  def reject_failed!(reviewer:)
    raise ArgumentError, 'No hay auditoria de imagenes.' unless batch
    raise ArgumentError, 'Termina de procesar todas las imagenes antes de aplicar rechazos.' if batch.items.pending.exists?

    failed_venue_ids = batch.failed_venue_ids
    rejected_count = 0

    BlackCoffeeImageAuditBatch.transaction do
      rejected_count = Venue
                       .where(id: failed_venue_ids, review_status: Venue::REVIEW_STATUS_PENDING)
                       .update_all(
                         review_status: Venue::REVIEW_STATUS_REJECTED,
                         review_rejection_reason: IMAGE_REJECTION_REASON,
                         review_rejection_note: rejection_note(batch),
                         reviewed_at: Time.current,
                         reviewed_by_id: reviewer&.id,
                         updated_at: Time.current
                       )

      batch.update!(
        status: 'rejected',
        rejected_venues_count: rejected_count,
        rejected_at: Time.current,
        rejected_by_id: reviewer&.id
      )
      refresh_counts!(batch)
    end

    rejected_count
  end

  private

  attr_reader :batch, :base_url, :limit, :checker

  def item_row(batch:, venue:, venue_image: nil, image_url: nil, status:, error_type: nil, error_message: nil, checked_at: nil)
    now = Time.current
    {
      black_coffee_image_audit_batch_id: batch.id,
      venue_id: venue.id,
      venue_image_id: venue_image&.id,
      venue_name: venue.name,
      image_url: image_url,
      status: status,
      error_type: error_type,
      error_message: error_message,
      checked_at: checked_at,
      created_at: now,
      updated_at: now
    }
  end

  def refresh_counts!(audit_batch)
    pending_venue_ids = audit_batch.items.pending.distinct.pluck(:venue_id)
    total_items = audit_batch.items.count
    failed_items = audit_batch.items.failed.count
    checked_items = audit_batch.items.checked.count
    failed_venues = audit_batch.items.failed.select(:venue_id).distinct.count
    status =
      if audit_batch.rejected?
        'rejected'
      elsif audit_batch.failed?
        'failed'
      elsif audit_batch.items.pending.exists?
        checked_items.positive? ? 'running' : 'pending'
      else
        'completed'
      end

    audit_batch.update_columns(
      status: status,
      processed_venues: [audit_batch.total_venues.to_i - pending_venue_ids.size, 0].max,
      total_images: total_items,
      checked_images: checked_items,
      failed_images_count: failed_items,
      failed_venues_count: failed_venues,
      completed_at: status == 'completed' ? (audit_batch.completed_at || Time.current) : audit_batch.completed_at,
      report_payload: report_payload_for(audit_batch),
      updated_at: Time.current
    )
    audit_batch.reload
  end

  def report_payload_for(audit_batch)
    failed_scope = audit_batch.items.failed
    {
      error_breakdown: failed_scope.group(:error_type).count,
      sample_failures: failed_scope.ordered.limit(25).map do |item|
        {
          venue_id: item.venue_id,
          venue_name: item.venue_name,
          image_url: item.image_url,
          error_type: item.error_type,
          http_status: item.http_status,
          error_message: item.error_message
        }
      end
    }
  end

  def rejection_note(audit_batch)
    "Rechazado por auditoria de imagenes Black Coffee ##{audit_batch.id}: imagenes ausentes o que no cargan."
  end

  def flush_rows!(rows, force: false)
    return if rows.empty?
    return if !force && rows.size < INSERT_BATCH_SIZE

    BlackCoffeeImageAuditItem.insert_all!(rows)
    rows.clear
  end

  class ImageChecker
    MAX_REDIRECTS = 4
    HEAD_FALLBACK_CODES = [403, 405, 501].freeze

    def check(url)
      return failure('missing_image', 'El local no tiene imagenes guardadas.') if url.blank?

      uri = URI.parse(url)
      return failure('invalid_url', 'La URL no usa http o https.') unless uri.is_a?(URI::HTTP)

      response = request_with_redirects(uri)
      code = response.code.to_i

      return success(code) if code.between?(200, 299) && image_response?(response)
      return failure('not_image', "La URL responde #{code}, pero no parece una imagen.", code) if code.between?(200, 299)

      failure('http_error', "La imagen responde HTTP #{code}.", code)
    rescue URI::InvalidURIError => e
      failure('invalid_url', e.message)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      failure('timeout', e.message)
    rescue SocketError, SystemCallError => e
      failure('network_error', e.message)
    rescue StandardError => e
      failure('unknown_error', e.message)
    end

    private

    def request_with_redirects(uri, redirects = 0)
      response = head(uri)

      if redirect?(response) && redirects < MAX_REDIRECTS
        location = response['location'].to_s
        return response if location.blank?

        return request_with_redirects(URI.join(uri, location), redirects + 1)
      end

      return ranged_get(uri) if HEAD_FALLBACK_CODES.include?(response.code.to_i)

      response
    end

    def head(uri)
      request(uri, Net::HTTP::Head.new(uri))
    end

    def ranged_get(uri)
      req = Net::HTTP::Get.new(uri)
      req['Range'] = 'bytes=0-0'
      request(uri, req)
    end

    def request(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 3, read_timeout: 4) do |http|
        http.request(request)
      end
    end

    def redirect?(response)
      response.code.to_i.between?(300, 399)
    end

    def image_response?(response)
      content_type = response['content-type'].to_s.downcase
      content_type.blank? || content_type.start_with?('image/')
    end

    def success(http_status)
      CheckResult.new(status: 'ok', http_status: http_status)
    end

    def failure(error_type, message, http_status = nil)
      CheckResult.new(status: 'failed', error_type: error_type, http_status: http_status, error_message: message)
    end
  end
end
