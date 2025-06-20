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

    if user_in_active_call?(receiver.id)
      return render json: { error: "User is already in a call" }, status: :bad_request
    end

    channel_name = generate_channel_name(current_user.id, receiver.id)

    # Guardamos temporalmente esta llamada para validación futura
    Rails.cache.write("temp_call:#{current_user.id}", {
      receiver_id: receiver.id,
      channel_name: channel_name
    }, expires_in: 2.minutes)

    ActionCable.server.broadcast("call_#{receiver.id}", {
      type: "incoming_call",
      caller_id: current_user.id,
      channel_name: channel_name
    })

    render json: { success: true, message: "Call request sent", channel_name: channel_name }
  end

  # 2. Aceptar llamada (sin necesidad de pasar caller_id desde el frontend)
    def accept
    # Buscar la llamada temporal que se envió previamente
    temp_call = Rails.cache.read_multi(*Rails.cache.instance_variable_get(:@data).keys)
                          .select { |k, v| k.start_with?("temp_call:") }
                          .find { |_, v| v[:receiver_id] == current_user.id }

    return render json: { error: "No call found" }, status: :not_found unless temp_call

    caller_id = temp_call[0].split(":").last.to_i
    caller = User.find_by(id: caller_id)

    unless caller && UserMatchRequest.match_confirmed_between?(caller, current_user)
      return render json: { error: "Invalid call" }, status: :forbidden
    end

    # Crear la llamada en la base de datos
    call = VideoCall.create!(
      user_1: caller,
      user_2: current_user,
      agora_channel_name: temp_call[1][:channel_name],
      status: :active,
      started_at: Time.current
    )

    Rails.cache.delete("temp_call:#{caller.id}")

    # ✅ Generar el token directamente aquí
    token = generate_token(
      channel: call.agora_channel_name,
      uid: current_user.id
    )

    # Notificar al otro usuario
    ActionCable.server.broadcast("call_#{caller.id}", {
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

  # 3. Rechazar llamada antes de que se cree en DB
  def reject
    temp_call = Rails.cache.read("temp_call:*").values.find do |v|
      v[:receiver_id] == current_user.id
    end

    return head :ok unless temp_call

    caller_id = Rails.cache.read("temp_call:*").key(temp_call).split(":").last.to_i
    Rails.cache.delete("temp_call:#{caller_id}")

    ActionCable.server.broadcast("call_#{caller_id}", {
      type: "call_rejected",
      receiver_id: current_user.id,
      channel_name: temp_call[:channel_name]
    })

    head :ok
  end

  # 4. Cancelar llamada antes de que se acepte
  def cancel
    temp_call = Rails.cache.read("temp_call:#{current_user.id}")

    return head :ok unless temp_call

    receiver_id = temp_call[:receiver_id]
    channel_name = temp_call[:channel_name]
    Rails.cache.delete("temp_call:#{current_user.id}")

    ActionCable.server.broadcast("call_#{receiver_id}", {
      type: "call_cancelled",
      caller_id: current_user.id,
      channel_name: channel_name
    })

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

  def generate_channel_name(user1_id, user2_id)
    "#{user1_id}-#{user2_id}-#{SecureRandom.hex(4)}"
  end

  def user_in_active_call?(user_id)
    VideoCall.where(status: :active)
             .where("user_1_id = ? OR user_2_id = ?", user_id, user_id)
             .exists?
  end
end
