class VideoCallsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!


    def generate_token(channel:, uid:)
      app_id = ENV.fetch("AGORA_APP_ID")
      app_cert = ENV.fetch("AGORA_APP_CERTIFICATE")
      expiration_seconds = 60
      current_timestamp = Time.now.to_i
      expire_timestamp = current_timestamp + expiration_seconds

      AgoraDynamicKey::RtcTokenBuilder.build_token_with_uid(
        app_id,
        app_cert,
        channel,
        uid,
        AgoraDynamicKey::RtcTokenBuilder::Role::PUBLISHER,
        expire_timestamp
      )
    end


  # 1. Solicitar llamada: solo se envía notificación al receptor
  def create
    receiver = User.find(params[:receiver_id])

    unless UserMatchRequest.match_confirmed_between?(current_user, receiver)
      return render json: { error: "No match" }, status: :forbidden
    end

    # Verifica si el receiver está conectado a ActionCable
    is_connected = ActionCable.server.connections.any? do |conn|
      conn.respond_to?(:current_user) && conn.current_user&.id == receiver.id
    end

    unless is_connected
      return render json: { error: "Receiver not connected" }, status: :bad_request
    end

    channel_name = get_channel_name(current_user.id, receiver.id)


    CallChannel.broadcast_to(receiver, {
      message: {
        type: "incoming_call",
        caller_id: current_user.id,
        channel_name: channel_name
      }
    })
        
    render json: { success: true }
  end

  # 2. Aceptar llamada (sin necesidad de pasar caller_id desde el frontend)
    def accept
  # Buscar el caller_id de la llamada pendiente para el usuario actual
  caller_id = Rails.cache.read("pending_call_for:#{current_user.id}")
  return render json: { error: "No call found" }, status: :not_found unless caller_id

  temp_call = Rails.cache.read("temp_call:#{caller_id}")
  return render json: { error: "No call found" }, status: :not_found unless temp_call

  caller = User.find_by(id: caller_id)

  unless caller && UserMatchRequest.match_confirmed_between?(caller, current_user)
    return render json: { error: "Invalid call" }, status: :forbidden
  end

  # Crear la llamada en la base de datos
  call = VideoCall.create!(
    user_1: caller,
    user_2: current_user,
    agora_channel_name: temp_call[:channel_name],
    status: :active,
    started_at: Time.current
  )

  # Limpiar las claves temporales
  Rails.cache.delete("temp_call:#{caller_id}")
  Rails.cache.delete("pending_call_for:#{current_user.id}")

  # ✅ Generar el token directamente aquí
  token = generate_token(
    channel: call.agora_channel_name,
    uid: current_user.id
  )

  # Notificar al otro usuario
  CallChannel.broadcast_to(caller, {
    message: {
    type: "call_accepted",
    receiver_id: current_user.id,
    channel_name: call.agora_channel_name
    }
  })

  render json: {
    token: token,
    uid: current_user.id,
    channel_name: call.agora_channel_name
  }
end

  # 3. Rechazar llamada antes de que se cree en DB
  def reject
  caller_id = params[:caller_id]
  return head :ok unless caller_id

  caller = User.find_by(id: caller_id)
  return head :ok unless caller

  CallChannel.broadcast_to(caller, {
    message: {
    type: "call_rejected",
    receiver_id: current_user.id
    }
  })

  head :ok
end

  # 4. Cancelar llamada antes de que se acepte
  def cancel
    receiver_id = params[:receiver_id]
    Rails.logger.info("Cancel request: receiver_id=#{receiver_id}, current_user=#{current_user.id}")
    return head :ok unless receiver_id

    receiver = User.find_by(id: receiver_id)
    Rails.logger.info("Cancel: found receiver? #{receiver.present?}")
    return head :ok unless receiver

    CallChannel.broadcast_to(receiver, {
      message: {
        type: "call_cancelled",
        caller_id: current_user.id
      }
    })
    Rails.logger.info("Cancel: broadcast sent to receiver #{receiver.id}")

    head :ok
  end

  # 5. Finalizar llamada
  def end_call
    call = VideoCall.find_by!(agora_channel_name: params[:channel_name])
    call.update!(status: :ended, ended_at: Time.current)
    call.calculate_duration! if call.respond_to?(:calculate_duration!)

    head :ok
  end

  # 6. Ver si el usuario está en una llamada activa
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

  private

  def get_channel_name(caller_id, receiver_id)
    "#{caller_id}-#{receiver_id}"
  end

  def user_in_active_call?(user_id)
    VideoCall.where(status: :active)
             .where("user_1_id = ? OR user_2_id = ?", user_id, user_id)
             .exists?
  end
end
