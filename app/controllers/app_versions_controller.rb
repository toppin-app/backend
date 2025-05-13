class AppVersionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show]
  skip_before_action :verify_authenticity_token, only: [:show]

  def show
    result = ActiveRecord::Base.connection.exec_query("SELECT * FROM app_versions LIMIT 1")

    if result.any?
      version = result.first
      render json: {
        android_last_version: version["android_last_version"],
        android_last_version_required: version["android_last_version_required"],
        ios_last_version: version["ios_last_version"],
        ios_last_version_required: version["ios_last_version_required"],
        android_store_link: version["android_store_link"],
        ios_store_link: version["ios_store_link"]
      }
    else
      render json: { error: "No version found" }, status: :not_found
    end
  end

  def invalid_post
    render json: { error: "POST method is not allowed for /app_version" }, status: :method_not_allowed
  end

  def index
    @app_versions = AppVersion.all
  end

  def edit
    @app_version = AppVersion.find(params[:id])
  end

  def update
    @app_version = AppVersion.find(params[:id])
    if @app_version.update(app_version_params)
      redirect_to app_versions_path, notice: 'Versión actualizada correctamente.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def app_version_params
    params.require(:app_version).permit(
      :android_last_version,
      :android_last_version_required,
      :ios_last_version,
      :ios_last_version_required,
      :android_store_link,
      :ios_store_link
    )
  end
end
