class TmdbController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!, except: [:search_movies, :search_series]

  # GET /tmdb_token
  def token
    bearer_token = ENV['TMDB_BEARER_TOKEN']
    render json: {
      token_type: "Bearer",
      access_token: bearer_token
    }
  end

  # GET /tmdb/search_movies?query=titulo
  def search_movies
    require 'net/http'
    require 'json'
    
    query = params[:query]
    return render json: [] if query.blank?

    uri = URI("https://api.themoviedb.org/3/search/movie?query=#{URI.encode_www_form_component(query)}&language=es-ES")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{ENV['TMDB_BEARER_TOKEN']}"
    request["accept"] = 'application/json'

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      results = data['results'].first(10).map do |movie|
        {
          id: movie['id'],
          title: movie['title'],
          poster_path: movie['poster_path'],
          release_date: movie['release_date']
        }
      end
      render json: results
    else
      render json: []
    end
  rescue => e
    Rails.logger.error "Error searching movies: #{e.message}"
    render json: []
  end

  # GET /tmdb/search_series?query=titulo
  def search_series
    require 'net/http'
    require 'json'
    
    query = params[:query]
    return render json: [] if query.blank?

    uri = URI("https://api.themoviedb.org/3/search/tv?query=#{URI.encode_www_form_component(query)}&language=es-ES")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{ENV['TMDB_BEARER_TOKEN']}"
    request["accept"] = 'application/json'

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      results = data['results'].first(10).map do |series|
        {
          id: series['id'],
          title: series['name'],
          poster_path: series['poster_path'],
          first_air_date: series['first_air_date']
        }
      end
      render json: results
    else
      render json: []
    end
  rescue => e
    Rails.logger.error "Error searching series: #{e.message}"
    render json: []
  end
end
