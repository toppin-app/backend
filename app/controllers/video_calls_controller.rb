require 'dynamic_key'
class VideoCallsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!

  def build_agora_token(channel:, uid:, expiration_seconds: 180)
    app_id = ENV.fetch("AGORA_APP_ID")
    app_cert = ENV.fetch("AGORA_APP_CERTIFICATE")
    current_timestamp = Time.now.to_i
    expire_timestamp = expiration_seconds + current_timestamp

    AgoraDynamicKey::RTCTokenBuilder.build_token_with_uid(
      app_id: app_id,
      app_certificate: app_cert,
      channel_name: channel,
      uid: uid,
      role: AgoraDynamicKey::RTCTokenBuilder::Role::PUBLISHER,
      privilege_expired_ts: expire_timestamp
    )
  end

  # 1. Solicitar llamada
  def create
    receiver = User.find(params[:receiver_id])

    unless UserMatchRequest.match_confirmed_between?(current_user, receiver)
      return render json: { error: "No match" }, status: :forbidden
    end

    total_seconds = VideoCall.duration(current_user, receiver).to_i
    max_seconds = 180

    unless current_user.premium_or_supreme? || receiver.premium_or_supreme?
      if total_seconds >= max_seconds
        return render json: { error: "Tiempo de videollamada agotado" }, status: :forbidden
      end
    end

    is_connected = ActionCable.server.connections.any? do |conn|
      conn.respond_to?(:current_user) && conn.current_user&.id == receiver.id
    end

    unless is_connected
      return render json: { error: "Receiver not connected" }, status: :bad_request
    end

    channel_name = get_channel_name(current_user.id, receiver.id)

    # Crea el registro de la llamada si no existe
    video_call = VideoCall.between(current_user, receiver).find_or_initialize_by(agora_channel_name: channel_name, status: :pending)
    video_call.user_1 = current_user
    video_call.user_2 = receiver
    video_call.started_at = Time.current
    video_call.status = :pending
    video_call.save!
    # Notifica al receptor de la llamada entrante
    CallChannel.broadcast_to(receiver, {
      message: {
        type: "incoming_call",
        caller_id: current_user.id,
        channel_name: channel_name
      }
    })

    render json: { success: true }
  end

  # 2. Aceptar llamada
  def accept
    caller = User.find_by(id: params[:caller_id])
    return render json: { error: "Caller not found" }, status: :not_found unless caller

    unless UserMatchRequest.match_confirmed_between?(caller, current_user)
      return render json: { error: "Invalid call" }, status: :forbidden
    end

    channel_name = get_channel_name(caller.id, current_user.id)

    # Actualiza el estado de la llamada a 'active'
    video_call = VideoCall.between(caller, current_user)
                          .where(agora_channel_name: channel_name, status: :pending)
                          .order(created_at: :desc)
                          .first
    if video_call
      attrs = { status: :active }
      attrs[:started_at] = Time.current unless video_call.started_at
      video_call.update!(attrs)
    end
    # Notifica al llamador que la llamada ha sido aceptada

    CallChannel.broadcast_to(caller, {
      message: {
        type: "call_accepted",
        receiver_id: current_user.id,
        channel_name: channel_name
      }
    })

    head :ok
  end

  # 3. Rechazar llamada
  def reject
    caller = User.find_by(id: params[:caller_id])
    return head :ok unless caller

    channel_name = get_channel_name(caller.id, current_user.id)

    CallChannel.broadcast_to(caller, {
      message: {
        type: "call_rejected",
        receiver_id: current_user.id
      }
    })

    head :ok
  end

  # 4. Cancelar llamada
  def cancel
    receiver = User.find_by(id: params[:receiver_id])
    return head :ok unless receiver

    channel_name = get_channel_name(current_user.id, receiver.id)

    CallChannel.broadcast_to(receiver, {
      message: {
        type: "call_cancelled",
        caller_id: current_user.id
      }
    })

    head :ok
  end

  # 5. Finalizar llamada
  def end_call
    Rails.logger.info "Entrando en end_call con params: #{params.inspect}"
    call = VideoCall.find_by(agora_channel_name: params[:channel_name])
    if call
      ended_at = Time.current
      duration = call.started_at ? (ended_at - call.started_at).to_i : 0
      Rails.logger.info "Actualizando llamada #{call.id} con ended_at=#{ended_at} y duration=#{duration}"
      call.update!(status: :ended, ended_at: ended_at, duration: duration)
    else
      Rails.logger.warn "No se encontró la llamada con channel_name=#{params[:channel_name]}"
    end
    head :ok
  end

  # 6. Ver si el usuario está en una llamada activa
  def active
    render json: { active: false }
  end

  # 7. Obtener token RTC
  def generate_token
    caller = User.find_by(id: params[:caller_id])
    receiver = User.find_by(id: params[:receiver_id])

    return render json: { error: "User not found" }, status: :bad_request unless caller && receiver

    channel_name = get_channel_name(caller.id, receiver.id)
    unless UserMatchRequest.match_confirmed_between?(caller, receiver)
      return render json: { error: "No match" }, status: :forbidden
    end
    # Si alguno es premium/supreme, tiempo "infinito" (10 años)
    if caller.premium_or_supreme? || receiver.premium_or_supreme?
      time_left = 315360000 # 10 años en segundos
    else
      max_seconds = 180
      used_seconds = VideoCall.duration(caller, receiver).to_i
      time_left = [max_seconds - used_seconds, 0].max
    end

     token = build_agora_token(
      channel: channel_name,
      uid: current_user.id,
      expiration_seconds: time_left
    )

    render json: {
      token: token,
      channel_name: channel_name,
      time_left: time_left,
      started_at: nil
    }
  end

  # GET /video_calls/match_status?user_id=OTRO_USER_ID
  def match_status
    render json: {
      ever_connected: false,
      last_channel_name: nil,
      last_started_at: nil,
      last_ended_at: nil,
      time_left: nil
    }
  end

  private

  def get_channel_name(caller_id, receiver_id)
    ids = [caller_id, receiver_id].sort
    "#{ids[0]}-#{ids[1]}"
  end
end
