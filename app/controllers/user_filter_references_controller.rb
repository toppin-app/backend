class UserFilterReferencesController < ApplicationController
  before_action :set_user_filter_reference, only: %i[ show edit update destroy ]

  # GET /user_filter_references or /user_filter_references.json
  def index
    @user_filter_references = UserFilterReference.all
  end

  # GET /user_filter_references/1 or /user_filter_references/1.json
  def show
  end

  # GET /user_filter_references/new
  def new
    @user_filter_reference = UserFilterReference.new
  end

  # GET /user_filter_references/1/edit
  def edit
  end

  # POST /user_filter_references or /user_filter_references.json
  def create
    @user_filter_reference = UserFilterReference.new(user_filter_reference_params)

    respond_to do |format|
      if @user_filter_reference.save
        format.html { redirect_to @user_filter_reference, notice: "User filter reference was successfully created." }
        format.json { render :show, status: :created, location: @user_filter_reference }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user_filter_reference.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /user_filter_references/1 or /user_filter_references/1.json
  def update
    respond_to do |format|
      if @user_filter_reference.update(user_filter_reference_params)
        format.html { redirect_to @user_filter_reference, notice: "User filter reference was successfully updated." }
        format.json { render :show, status: :ok, location: @user_filter_reference }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user_filter_reference.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /user_filter_references/1 or /user_filter_references/1.json
  def destroy
    @user_filter_reference.destroy
    respond_to do |format|
      format.html { redirect_to user_filter_references_url, notice: "User filter reference was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user_filter_reference
      @user_filter_reference = UserFilterReference.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def user_filter_reference_params
      params.require(:user_filter_reference).permit(:user_id, :gender, :distance_range, :age_from, :age_till)
    end
end
