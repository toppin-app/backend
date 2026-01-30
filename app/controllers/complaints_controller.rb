class ComplaintsController < ApplicationController
  before_action :set_complaint, only: %i[ show edit update destroy ]

  # GET /complaints or /complaints.json
  def index
    @complaints = Complaint.includes(:user, :reported_user).recent
    
    # Filtrar por razón si se especifica
    @complaints = @complaints.by_reason(params[:reason]) if params[:reason].present?
    
    # Filtrar por estado si se especifica
    @complaints = @complaints.where(status: params[:status]) if params[:status].present?
    
    # Filtrar por acción tomada si se especifica
    @complaints = @complaints.where(action_taken: params[:action_taken]) if params[:action_taken].present?
    
    # Obtener lista de razones únicas para el filtro
    @reasons = Complaint.distinct.pluck(:reason).compact.sort
    
    @title = "Denuncias"
  end

  # GET /complaints/1 or /complaints/1.json
  def show
  end

  # GET /complaints/new
  def new
    @complaint = Complaint.new
  end

  # GET /complaints/1/edit
  def edit
  end

  # POST /complaints or /complaints.json
  def create
    @complaint = Complaint.new(complaint_params)
    @complaint.user_id = current_user.id

    respond_to do |format|
      if @complaint.save
        format.html { redirect_to @complaint, notice: "Complaint was successfully created." }
        format.json { render :show, status: :created, location: @complaint }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @complaint.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /complaints/1 or /complaints/1.json
  def update
    respond_to do |format|
      if @complaint.update(complaint_params)
        # Si la acción es bloquear usuario, marcar al usuario como bloqueado
        # El block_reason_key se guarda automáticamente via after_save callback en Complaint
        if @complaint.action_taken == 'user_blocked' && @complaint.reported_user.present?
          @complaint.reported_user.update(blocked: true)
        end
        
        format.html { redirect_to complaints_url, notice: "Acción procesada correctamente." }
        format.json { render json: { success: true, message: "Acción procesada correctamente." }, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, error: @complaint.errors.full_messages.join(', ') }, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /complaints/1 or /complaints/1.json
  def destroy
    @complaint.destroy
    respond_to do |format|
      format.html { redirect_to complaints_url, notice: "Complaint was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_complaint
      @complaint = Complaint.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def complaint_params
      params.require(:complaint).permit(:user_id, :to_user_id, :reason, :text, :action_taken, :reason_key)
    end
end
