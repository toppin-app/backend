class TmdbController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!

  # GET /tmdb_token
  def token
    bearer_token = ENV['TMDB_BEARER_TOKEN']
    render json: {
      token_type: "Bearer",
      access_token: bearer_token
    }
  end
end
