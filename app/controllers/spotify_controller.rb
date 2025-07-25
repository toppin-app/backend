class SpotifyController < ApplicationController
  skip_before_action :verify_authenticity_token

  # GET /spotify_token
  def token
    client_id = ENV['SPOTIFY_CLIENT_ID']
    client_secret = ENV['SPOTIFY_CLIENT_SECRET']

    auth = Base64.strict_encode64("#{client_id}:#{client_secret}")

    response = Faraday.post('https://accounts.spotify.com/api/token',
      { grant_type: 'client_credentials' },
      { 'Authorization' => "Basic #{auth}", 'Content-Type' => 'application/x-www-form-urlencoded' }
    )

    render json: JSON.parse(response.body)
  end
end