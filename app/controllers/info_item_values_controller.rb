class InfoItemValuesController < ApplicationController
  before_action :set_info_item_value, only: %i[ show edit update destroy ]

  # GET /info_item_values or /info_item_values.json
  def index
    @info_item_values = InfoItemValue.all.order(name: :asc)
  end

  # GET /info_item_values/1 or /info_item_values/1.json
  def show
  end

  # GET /info_item_values/new
  def new
    @info_item_value = InfoItemValue.new
    @title = "Nuevo valor"
  end

  # GET /info_item_values/1/edit
  def edit
        @title = "Editar valor"
  end

  # POST /info_item_values or /info_item_values.json
  def create
    @info_item_value = InfoItemValue.new(info_item_value_params)

    respond_to do |format|
      if @info_item_value.save
        format.html { redirect_to @info_item_value.info_item_category, notice: "Valor creado con éxito" }
        format.json { render :show, status: :created, location: @info_item_value }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @info_item_value.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /info_item_values/1 or /info_item_values/1.json
  def update
    respond_to do |format|
      if @info_item_value.update(info_item_value_params)
        format.html { redirect_to @info_item_value.info_item_category, notice: "Valor actualizado con éxito" }
        format.json { render :show, status: :ok, location: @info_item_value }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @info_item_value.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /info_item_values/1 or /info_item_values/1.json
  def destroy
    cat = @info_item_value.info_item_category
    @info_item_value.destroy
    respond_to do |format|
      format.html { redirect_to cat, notice: "Valor eliminado con éxito" }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_info_item_value
      @info_item_value = InfoItemValue.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def info_item_value_params
      params.require(:info_item_value).permit(:name, :info_item_category_id)
    end
end
