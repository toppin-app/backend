class AppVersionsController < ApplicationController
  # Omite cualquier autenticación o filtros globales
  skip_before_action :authenticate_user!, only: [:show]
  skip_before_action :verify_authenticity_token, only: [:show] # Si aplica CSRF protection

  def show
    result = ActiveRecord::Base.connection.exec_query("SELECT * FROM app_versions LIMIT 1")

    if result.any?
      version = result.first
      render json: {
        android_last_version: version["android_last_version"],
        android_last_version_required: version["android_last_version_required"],
        ios_last_version: version["ios_last_version"],
        ios_last_version_required: version["ios_last_version_required"]
      }
    else
      render json: { error: "No version found" }, status: :not_found
    end
  end
end
