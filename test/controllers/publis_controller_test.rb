require 'test_helper'

class PublisControllerTest < ActionDispatch::IntegrationTest
  setup do
    @publi = publis(:one)
  end

  test "should get index" do
    get publis_url
    assert_response :success
  end

  test "should get new" do
    get new_publi_url
    assert_response :success
  end

  test "should create publi" do
    assert_difference('Publi.count') do
      post publis_url, params: { publi: { cancellable: @publi.cancellable, end_date: @publi.end_date, end_time: @publi.end_time, image: @publi.image, link: @publi.link, repeat_swipes: @publi.repeat_swipes, start_date: @publi.start_date, start_time: @publi.start_time, title: @publi.title, video: @publi.video, weekdays: @publi.weekdays } }
    end

    assert_redirected_to publi_url(Publi.last)
  end

  test "should show publi" do
    get publi_url(@publi)
    assert_response :success
  end

  test "should get edit" do
    get edit_publi_url(@publi)
    assert_response :success
  end

  test "should update publi" do
    patch publi_url(@publi), params: { publi: { cancellable: @publi.cancellable, end_date: @publi.end_date, end_time: @publi.end_time, image: @publi.image, link: @publi.link, repeat_swipes: @publi.repeat_swipes, start_date: @publi.start_date, start_time: @publi.start_time, title: @publi.title, video: @publi.video, weekdays: @publi.weekdays } }
    assert_redirected_to publi_url(@publi)
  end

  test "should destroy publi" do
    assert_difference('Publi.count', -1) do
      delete publi_url(@publi)
    end

    assert_redirected_to publis_url
  end
end
