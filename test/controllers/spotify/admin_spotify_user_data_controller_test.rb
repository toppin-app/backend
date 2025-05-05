require 'test_helper'

class Spotify::AdminSpotifyUserDataControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get spotify_admin_spotify_user_data_index_url
    assert_response :success
  end

  test "should get show" do
    get spotify_admin_spotify_user_data_show_url
    assert_response :success
  end

  test "should get new" do
    get spotify_admin_spotify_user_data_new_url
    assert_response :success
  end

  test "should get create" do
    get spotify_admin_spotify_user_data_create_url
    assert_response :success
  end

  test "should get edit" do
    get spotify_admin_spotify_user_data_edit_url
    assert_response :success
  end

  test "should get update" do
    get spotify_admin_spotify_user_data_update_url
    assert_response :success
  end

end
