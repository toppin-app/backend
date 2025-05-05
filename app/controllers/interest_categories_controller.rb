class InterestCategoriesController < ApplicationController
  before_action :set_interest_category, only: %i[ show edit update destroy ]

  # GET /interest_categories or /interest_categories.json
  def index
    @interest_categories = InterestCategory.all
    @title = "Categorías de interés"
  end

  # GET /interest_categories/1 or /interest_categories/1.json
  def show
    @title = @interest_category.name
        @interest = Interest.new
  end

  # GET /interest_categories/new
  def new
    @interest_category = InterestCategory.new
    @title = "Nueva categoría"

  end

  # GET /interest_categories/1/edit
  def edit
    @title = "Editar categoría"
  end

  # POST /interest_categories or /interest_categories.json
  def create
    @interest_category = InterestCategory.new(interest_category_params)

    respond_to do |format|
      if @interest_category.save
        format.html { redirect_to interest_categories_path, notice: "Categoría guardada con éxito." }
        format.json { render :show, status: :created, location: @interest_category }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @interest_category.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /interest_categories/1 or /interest_categories/1.json
  def update
    respond_to do |format|
      if @interest_category.update(interest_category_params)
        format.html { redirect_to interest_categories_path, notice: "Categoría editada con éxito" }
        format.json { render :show, status: :ok, location: @interest_category }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @interest_category.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /interest_categories/1 or /interest_categories/1.json
  def destroy
    @interest_category.destroy
    respond_to do |format|
      format.html { redirect_to interest_categories_url, notice: "Categoría eliminada con éxito." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_interest_category
      @interest_category = InterestCategory.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def interest_category_params
      params.require(:interest_category).permit(:name)
    end
end
