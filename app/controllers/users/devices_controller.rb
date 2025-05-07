class DevicesController < ApplicationController
  def register
    if current_user
      device = Device.register(params[:token], params[:so].downcase, params[:device_uid], current_user)
      render json: { status: 200, device: device }.as_json
    else
      render json: { status: 401, error: "Error registrando dispositivo, usuario no encontrado." }, status: 401
    end
  end
end