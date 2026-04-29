class BlackCoffeeSubcategoriesController < ApplicationController
  before_action :check_admin

  def index
    @title = 'Black Coffee - Subcategorias'
    @categories = Venue::CATEGORIES

    counts = Venue.joins(:venue_subcategory)
                  .group('venue_subcategories.category', 'venue_subcategories.name')
                  .count
    query = params[:q].to_s.strip.downcase
    selected_category = params[:category].presence
    selected_category = nil unless Venue::CATEGORIES.include?(selected_category)

    @subcategories = BlackCoffeeTaxonomy.subcategory_options(selected_category).filter_map do |entry|
      haystack = [entry[:name], entry[:label], Array(entry[:google_types]).join(' ')].join(' ').downcase
      next if query.present? && !haystack.include?(query)

      entry.merge(venues_count: counts[[entry[:category], entry[:name]]].to_i)
    end
  end

  def new
    redirect_to black_coffee_subcategories_path, alert: 'Las subcategorias son fijas y se actualizan por codigo.'
  end

  def edit
    redirect_to black_coffee_subcategories_path, alert: 'Las subcategorias son fijas y no se editan desde el dashboard.'
  end

  def create
    redirect_to black_coffee_subcategories_path, alert: 'Las subcategorias son fijas y se actualizan por codigo.'
  end

  def update
    redirect_to black_coffee_subcategories_path, alert: 'Las subcategorias son fijas y no se editan desde el dashboard.'
  end

  def destroy
    redirect_to black_coffee_subcategories_path, alert: 'Las subcategorias son fijas y no se eliminan desde el dashboard.'
  end
end
