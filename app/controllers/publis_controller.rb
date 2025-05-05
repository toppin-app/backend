class PublisController < ApplicationController
  before_action :set_publi, only: %i[ show edit update destroy ]

  # GET /publis or /publis.json
  def index
    @publis = Publi.all.order(id: :desc)
    @title = "Publicidad"
  end

  # GET /publis/1 or /publis/1.json
  def show
    @title = "Información del anuncio"
  end

  # GET /publis/new
  def new
    @publi = Publi.new
    @title = "Nuevo anuncio"
    set_weekdays
  end

  # GET /publis/1/edit
  def edit
      @title = "Editar anuncio"
      @edit = true
  end

  # POST /publis or /publis.json
  def create
    @publi = Publi.new(publi_params)
    process_weekdays
    respond_to do |format|
      if @publi.save
        format.html { redirect_to @publi, notice: "Anuncio creado con éxito." }
        format.json { render :show, status: :created, location: @publi }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @publi.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /publis/1 or /publis/1.json
  def update
    process_weekdays
    respond_to do |format|
      if @publi.update(publi_params)
        format.html { redirect_to @publi, notice: "Anuncio editado con éxito." }
        format.json { render :show, status: :ok, location: @publi }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @publi.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /publis/1 or /publis/1.json
  def destroy
    @publi.destroy
    respond_to do |format|
      format.html { redirect_to publis_url, notice: "Anuncio eliminado con éxito." }
      format.json { head :no_content }
    end
  end

  def process_weekdays
     weekdays = ""
     params[:publi][:weekdays].each do |weekday|
          if weekday.present?
              weekdays = weekdays+weekday+","
          end
      end
      weekdays = weekdays.chop
      @publi.weekdays = weekdays
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_publi
      @publi = Publi.find(params[:id])
      set_weekdays
    end

    def set_weekdays
      @weekdays = [["Lunes", 1], ["Martes", 2], ["Miércoles", 3], ["Jueves", 4], ["Viernes", 5], ["Sábado", 6], ["Domingo", 7]]
    end

    # Only allow a list of trusted parameters through.
    def publi_params
      params.require(:publi).permit(:title, :start_date, :end_date, :weekdays, :start_time, :end_time, :image, :video, :link, :cancellable, :repeat_swipes)
    end
end
