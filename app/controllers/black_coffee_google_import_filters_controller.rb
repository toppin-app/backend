class BlackCoffeeGoogleImportFiltersController < ApplicationController
  SUGGESTION_SAMPLE_LIMIT = 400

  before_action :check_admin
  before_action :set_categories
  before_action :set_filter, only: :update

  def index
    @title = 'Filtros Google del importador'
    @filters_by_category = @categories.index_with { |category| BlackCoffeeGoogleImportFilter.for_category(category) }
    @suggestions_by_category = build_suggestions_by_category
  end

  def update
    @filter.assign_attributes(parsed_filter_attributes)

    if @filter.save
      @filter.invalidate_google_totals!
      redirect_to black_coffee_google_filters_path(anchor: dom_id_for(@filter.category)),
                  notice: "Filtros actualizados para #{label_for(@filter.category)}. Los totales Google de esa categoria se han marcado para recalculo."
    else
      @title = 'Filtros Google del importador'
      @filters_by_category = @categories.index_with do |category|
        category == @filter.category ? @filter : BlackCoffeeGoogleImportFilter.for_category(category)
      end
      @suggestions_by_category = build_suggestions_by_category
      flash.now[:alert] = @filter.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  private

  def set_categories
    @categories = GooglePlacesBlackCoffeeClient.importable_categories
  end

  def set_filter
    @filter = BlackCoffeeGoogleImportFilter.for_category(params[:category])
  end

  def parsed_filter_attributes
    payload = params.fetch(:black_coffee_google_import_filter, {}).permit(
      :excluded_primary_types_text,
      :excluded_types_text,
      :excluded_keywords_text
    )

    {
      excluded_primary_types: split_input(payload[:excluded_primary_types_text], normalize: true),
      excluded_types: split_input(payload[:excluded_types_text], normalize: true),
      excluded_keywords: split_input(payload[:excluded_keywords_text], normalize: false)
    }
  end

  def split_input(raw_value, normalize:)
    Array(raw_value.to_s.split(/[\n,]/)).map do |entry|
      normalize ? BlackCoffeeTaxonomy.normalize_google_tag(entry) : entry.to_s.strip
    end.reject(&:blank?).uniq
  end

  def build_suggestions_by_category
    @categories.index_with { |category| suggestions_for(category) }
  end

  def suggestions_for(category)
    primary_type_counts = Hash.new(0)
    tag_counts = Hash.new(0)

    BlackCoffeeImportCandidate.where(category: category).order(id: :desc).limit(SUGGESTION_SAMPLE_LIMIT).pluck(:raw_payload).each do |raw_payload|
      payload = normalized_payload(raw_payload)
      primary_type = BlackCoffeeTaxonomy.normalize_google_tag(BlackCoffeeTaxonomy.place_value(payload, 'primaryType'))
      primary_type_counts[primary_type] += 1 if primary_type.present?

      BlackCoffeeTaxonomy.google_tags_for_place(payload).each do |tag|
        tag_counts[tag] += 1 if tag.present?
      end
    end

    Venue.where(category: category).order(id: :desc).limit(SUGGESTION_SAMPLE_LIMIT).pluck(:tags).each do |tags|
      normalized_tags(tags).each do |tag|
        normalized = BlackCoffeeTaxonomy.normalize_google_tag(tag)
        tag_counts[normalized] += 1 if normalized.present?
      end
    end

    {
      primary_types: primary_type_counts.sort_by { |type, count| [generic_tag_sort_key(type), -count, type] }.first(12),
      tags: tag_counts.sort_by { |tag, count| [generic_tag_sort_key(tag), -count, tag] }.first(18)
    }
  end

  def generic_tag_sort_key(tag)
    BlackCoffeeGoogleImportFilter::GENERIC_GOOGLE_TAGS.include?(tag) ? 1 : 0
  end

  def normalized_payload(raw_payload)
    payload =
      if raw_payload.respond_to?(:with_indifferent_access)
        raw_payload
      elsif raw_payload.is_a?(String)
        JSON.parse(raw_payload)
      else
        {}
      end

    payload.respond_to?(:with_indifferent_access) ? payload.with_indifferent_access : {}
  rescue JSON::ParserError
    {}
  end

  def normalized_tags(raw_tags)
    case raw_tags
    when Array
      raw_tags
    when String
      JSON.parse(raw_tags)
    else
      []
    end
  rescue JSON::ParserError
    []
  end

  def dom_id_for(category)
    "category-filter-#{category}"
  end

  def label_for(category)
    GooglePlacesBlackCoffeeClient.config_for(category).fetch(:label)
  end
end
