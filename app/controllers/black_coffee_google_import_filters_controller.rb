class BlackCoffeeGoogleImportFiltersController < ApplicationController
  SUGGESTION_SAMPLE_LIMIT = 400

  before_action :check_admin
  before_action :set_categories
  before_action :set_filter, only: :update

  def index
    @title = 'Filtros Google del importador'
    @global_filter = BlackCoffeeGoogleImportFilter.global
    @filters_by_category = @categories.index_with { |category| BlackCoffeeGoogleImportFilter.for_category(category) }
    @google_tag_catalog = BlackCoffeeGoogleTagCatalog.all_tags
  end

  def update
    @filter.assign_attributes(parsed_filter_attributes)

    if @filter.save
      @filter.invalidate_google_totals!
      redirect_to black_coffee_google_filters_path(anchor: dom_id_for(@filter.category)),
                  notice: success_message_for(@filter)
    else
      @title = 'Filtros Google del importador'
      @global_filter = @filter.global? ? @filter : BlackCoffeeGoogleImportFilter.global
      @filters_by_category = @categories.index_with do |category|
        category == @filter.category ? @filter : BlackCoffeeGoogleImportFilter.for_category(category)
      end
      @google_tag_catalog = BlackCoffeeGoogleTagCatalog.all_tags
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

  def dom_id_for(category)
    "category-filter-#{category}"
  end

  def success_message_for(filter)
    if filter.global?
      'Filtros globales actualizados. Los totales Google guardados se han marcado para recalculo en todas las categorias.'
    else
      "Filtros actualizados para #{filter.label}. Los totales Google de esa categoria se han marcado para recalculo."
    end
  end
end
