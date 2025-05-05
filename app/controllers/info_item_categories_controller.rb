class InfoItemCategoriesController < ApplicationController
  before_action :set_info_item_category, only: %i[ show edit update destroy ]

  # GET /info_item_categories or /info_item_categories.json
  def index
    @info_item_categories = []


    @info_item_categories = InfoItemCategory.where(id: 8).includes(:info_item_values)
    @info_item_categories = @info_item_categories + InfoItemCategory.where.not(id: 8).includes(:info_item_values)

    @title = "Categorías de perfil"
  end

  # GET /info_item_categories/1 or /info_item_categories/1.json
  def show
        @info_item_value = InfoItemValue.new
        @title = @info_item_category.name
  end

  # GET /info_item_categories/new
  def new
    @info_item_category = InfoItemCategory.new
    @title = "Nueva categoría de perfil"
  end

  # GET /info_item_categories/1/edit
  def edit
    @title = "Editar categoría de perfil"
  end

  # POST /info_item_categories or /info_item_categories.json
  def create
    @info_item_category = InfoItemCategory.new(info_item_category_params)

    respond_to do |format|
      if @info_item_category.save
        format.html { redirect_to @info_item_category, notice: "Info item category was successfully created." }
        format.json { render :show, status: :created, location: @info_item_category }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @info_item_category.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /info_item_categories/1 or /info_item_categories/1.json
  def update
    respond_to do |format|
      if @info_item_category.update(info_item_category_params)
        format.html { redirect_to @info_item_category, notice: "Info item category was successfully updated." }
        format.json { render :show, status: :ok, location: @info_item_category }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @info_item_category.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /info_item_categories/1 or /info_item_categories/1.json
  def destroy
    @info_item_category.destroy
    respond_to do |format|
      format.html { redirect_to info_item_categories_url, notice: "Info item category was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_info_item_category
      @info_item_category = InfoItemCategory.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def info_item_category_params
      params.require(:info_item_category).permit(:name)
    end
end
