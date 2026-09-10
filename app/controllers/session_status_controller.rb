class SessionStatusController < ApplicationController
  skip_before_action :authenticate_user!, :check_if_user_blocked, :save_last_connection

  # Decode the supplied JWT explicitly: a Rails session cookie must never
  # make an expired, revoked or missing bearer token appear valid.
  def show
    response.headers['Cache-Control'] = 'no-store'
    match = request.headers['Authorization'].to_s.match(/\ABearer (\S+)\z/i)
    return head :unauthorized unless match

    user = Warden::JWTAuth::UserDecoder.new.call(match[1], :user, nil)
    return head :unauthorized unless user && user.active_for_authentication?
    return head :forbidden if user.blocked?

    render json: { id: user.id }
  rescue JWT::DecodeError
    head :unauthorized
  end
end
