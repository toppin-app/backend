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
        caller_name: current_user.name,
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
        channel_name: channel_name,
        started_at: video_call.started_at
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
      time_left = 864000 # 24 horas en segundos
    # Si no, calculamos el tiempo restante de la llamada
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
    other_user = User.find_by(id: params[:user_id])
    return render json: { error: "User not found" }, status: :not_found unless other_user

    calls = VideoCall.between(current_user, other_user)
                     .where.not(status: [:pending, :rejected, :cancelled])
                     .order(started_at: :desc)
    last_call = calls.first

    last_video_call_date = last_call&.started_at

    if current_user.premium_or_supreme? || other_user.premium_or_supreme?
      time_left = 864000 # 24 horas en segundos
      has_unlimited_time = true
    else
      max_seconds = 180
      used_seconds = VideoCall.duration(current_user, other_user).to_i
      time_left = [max_seconds - used_seconds, 0].max
      has_unlimited_time = false
    end

    render json: {
      has_unlimited_time: has_unlimited_time,
      last_video_call_date: last_video_call_date,
      time_left: time_left
    }
  end

  private

  def get_channel_name(caller_id, receiver_id)
    ids = [caller_id, receiver_id].sort
    "#{ids[0]}-#{ids[1]}"
  end
end
