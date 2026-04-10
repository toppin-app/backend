class BlackCoffeeSubcategoriesController < ApplicationController
  before_action :check_admin
  before_action :set_subcategory, only: [:edit, :update, :destroy]

  def index
    @title = 'Black Coffee - Subcategorias'
    @categories = Venue::CATEGORIES

    scope = VenueSubcategory.left_joins(:venues)
    scope = scope.where(category: params[:category]) if params[:category].present? && Venue::CATEGORIES.include?(params[:category])
    scope = scope.where('venue_subcategories.name LIKE ?', "%#{params[:q].to_s.strip}%") if params[:q].to_s.strip.present?

    @subcategories = scope.group('venue_subcategories.id')
                          .order(:category, :name)
                          .select('venue_subcategories.*, COUNT(venues.id) AS venues_count')
  end

  def new
    @subcategory = VenueSubcategory.new
    @title = 'Nueva subcategoria Black Coffee'
    @categories = Venue::CATEGORIES
  end

  def edit
    @title = "Editar subcategoria #{@subcategory.name}"
    @categories = Venue::CATEGORIES
  end

  def create
    @subcategory = VenueSubcategory.new(subcategory_params)
    @categories = Venue::CATEGORIES
    @title = 'Nueva subcategoria Black Coffee'

    if @subcategory.save
      redirect_to black_coffee_subcategories_path, notice: 'Subcategoria creada correctamente.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @categories = Venue::CATEGORIES
    @title = "Editar subcategoria #{@subcategory.name}"

    if @subcategory.update(update_subcategory_params)
      redirect_to black_coffee_subcategories_path, notice: 'Subcategoria actualizada correctamente.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @subcategory.destroy
    redirect_to black_coffee_subcategories_path, notice: 'Subcategoria eliminada correctamente.'
  end

  private

  def set_subcategory
    @subcategory = VenueSubcategory.find(params[:id])
  end

  def subcategory_params
    params.require(:venue_subcategory).permit(:name, :category)
  end

  def update_subcategory_params
    params.require(:venue_subcategory).permit(:name)
  end
end
