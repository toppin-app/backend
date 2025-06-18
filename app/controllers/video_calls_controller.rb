class VideoCallsController < ApplicationController
  before_action :authenticate_user!

  # 1. Crear una nueva llamada (iniciar llamada)
  def create
    other_user = User.find(params[:user_id])

    unless Match.exists_between?(current_user, other_user)
      return render json: { error: "No match" }, status: :forbidden
    end

    agora_channel = "#{current_user.id}-#{other_user.id}-#{SecureRandom.hex(4)}"

    call = VideoCall.create!(
      user_1: current_user,
      user_2: other_user,
      agora_channel_name: agora_channel,
      status: :pending,
      started_at: Time.current
    )

    token = Agora::TokenGenerator.generate(
      channel: call.agora_channel_name,
      uid: current_user.id
    )

    # Notificar al otro usuario por ActionCable
    ActionCable.server.broadcast("call_#{other_user.id}", {
      type: "incoming_call",
      caller_id: current_user.id,
      channel_name: call.agora_channel_name
    })

    render json: {
      channel_name: call.agora_channel_name,
      token: token,
      uid: current_user.id
    }
  end

  # 2. Aceptar la llamada
  def accept
    call = VideoCall.find_by!(agora_channel_name: params[:channel_name])
    call.update!(status: :active)

    token = Agora::TokenGenerator.generate(
      channel: call.agora_channel_name,
      uid: current_user.id
    )

    other_user_id = (call.user_1_id == current_user.id ? call.user_2_id : call.user_1_id)

    ActionCable.server.broadcast("call_#{other_user_id}", {
      type: "call_accepted",
      receiver_id: current_user.id,
      channel_name: call.agora_channel_name
    })

    render json: {
      token: token,
      uid: current_user.id,
      channel_name: call.agora_channel_name
    }
  end

  # 3. Rechazar la llamada
  def reject
    call = VideoCall.find_by!(agora_channel_name: params[:channel_name])
    call.update!(status: :ended, ended_at: Time.current)

    other_user_id = (call.user_1_id == current_user.id ? call.user_2_id : call.user_1_id)

    ActionCable.server.broadcast("call_#{other_user_id}", {
      type: "call_rejected",
      receiver_id: current_user.id,
      channel_name: call.agora_channel_name
    })

    head :ok
  end

  # 4. Cancelar la llamada (por parte del que la inicia)
  def cancel
    call = VideoCall.find_by!(agora_channel_name: params[:channel_name])
    call.update!(status: :ended, ended_at: Time.current)

    other_user_id = (call.user_1_id == current_user.id ? call.user_2_id : call.user_1_id)

    ActionCable.server.broadcast("call_#{other_user_id}", {
      type: "call_cancelled",
      caller_id: current_user.id,
      channel_name: call.agora_channel_name
    })

    head :ok
  end

  # 5. Finalizar llamada
  def end_call
    call = VideoCall.find_by!(agora_channel_name: params[:channel_name])
    call.update!(
      status: :ended,
      ended_at: Time.current
    )
    call.calculate_duration! if call.respond_to?(:calculate_duration!)

    head :ok
  end

  # 6. Verificar si un usuario está en llamada activa (similar al isUserInCall)
  def active
    call = VideoCall.where(status: :active)
                    .where("user_1_id = ? OR user_2_id = ?", current_user.id, current_user.id)
                    .order(created_at: :desc)
                    .first

    if call
      render json: {
        active: true,
        channel_name: call.agora_channel_name,
        other_user_id: (call.user_1_id == current_user.id ? call.user_2_id : call.user_1_id)
      }
    else
      render json: { active: false }
    end
  end
end
