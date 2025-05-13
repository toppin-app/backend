class InterestsController < ApplicationController
  skip_before_action :authenticate_user!, except: [:index]
  before_action :set_interest, only: %i[ show edit update destroy ]

  # GET /interests or /interests.json
  def index
    @interests = Interest.all
    @title = "Intereses"

      respond_to do |format|
        format.html { @interests = @interests.paginate(:page => params[:page], :per_page => 15) }
        format.json {}
      end

  end

  # GET /interests/1 or /interests/1.json
  def show
  end

  # GET /interests/new
  def new
    @interest = Interest.new
    @title = "Nuevo interés"
  end

  # GET /interests/1/edit
  def edit
    @title = "Editar interés"
  end

  # POST /interests or /interests.json
  def create
    @interest = Interest.new(interest_params)

    respond_to do |format|
      if @interest.save
        format.html { redirect_to @interest.interest_category, notice: "Interés creado con éxito." }
        format.json { render :show, status: :created, location: @interest }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @interest.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /interests/1 or /interests/1.json
  def update
    respond_to do |format|
      if @interest.update(interest_params)
        format.html { redirect_to @interest.interest_category, notice: "Interés editado con éxito." }
        format.json { render :show, status: :ok, location: @interest }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @interest.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /interests/1 or /interests/1.json
  def destroy
    cat = @interest.interest_category
    @interest.destroy
    respond_to do |format|
      format.html { redirect_to cat, notice: "Interés eliminado con éxito" }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_interest
      @interest = Interest.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def interest_params
      params.require(:interest).permit(:interest_category_id, :name)
    end
end
