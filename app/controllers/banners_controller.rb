class BannersController < ApplicationController
  before_action :set_banner, only: %i[show edit update destroy]
  before_action :check_admin

  # GET /banners
  def index
    @banners = Banner.all.order(created_at: :desc)
  end

  # GET /banners/1
  def show
  end

  # GET /banners/new
  def new
    @banner = Banner.new
  end

  # GET /banners/1/edit
  def edit
  end

  # POST /banners
  def create
    @banner = Banner.new(banner_params)

    respond_to do |format|
      if @banner.save
        format.html { redirect_to @banner, notice: 'Banner creado exitosamente.' }
        format.json { render :show, status: :created, location: @banner }
      else
        format.html { render :new }
        format.json { render json: @banner.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /banners/1
  def update
    respond_to do |format|
      if @banner.update(banner_params)
        format.html { redirect_to @banner, notice: 'Banner actualizado exitosamente.' }
        format.json { render :show, status: :ok, location: @banner }
      else
        format.html { render :edit }
        format.json { render json: @banner.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /banners/1
  def destroy
    @banner.destroy
    respond_to do |format|
      format.html { redirect_to banners_url, notice: 'Banner eliminado exitosamente.' }
      format.json { head :no_content }
    end
  end

  private

  def set_banner
    @banner = Banner.find(params[:id])
  end

  def banner_params
    params.require(:banner).permit(:title, :description, :image, :url, :active, :start_date, :end_date)
  end
end