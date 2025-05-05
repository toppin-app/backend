require "application_system_test_case"

class PublisTest < ApplicationSystemTestCase
  setup do
    @publi = publis(:one)
  end

  test "visiting the index" do
    visit publis_url
    assert_selector "h1", text: "Publis"
  end

  test "creating a Publi" do
    visit publis_url
    click_on "New Publi"

    check "Cancellable" if @publi.cancellable
    fill_in "End date", with: @publi.end_date
    fill_in "End time", with: @publi.end_time
    fill_in "Image", with: @publi.image
    fill_in "Link", with: @publi.link
    fill_in "Repeat swipes", with: @publi.repeat_swipes
    fill_in "Start date", with: @publi.start_date
    fill_in "Start time", with: @publi.start_time
    fill_in "Title", with: @publi.title
    fill_in "Video", with: @publi.video
    fill_in "Weekdays", with: @publi.weekdays
    click_on "Create Publi"

    assert_text "Publi was successfully created"
    click_on "Back"
  end

  test "updating a Publi" do
    visit publis_url
    click_on "Edit", match: :first

    check "Cancellable" if @publi.cancellable
    fill_in "End date", with: @publi.end_date
    fill_in "End time", with: @publi.end_time
    fill_in "Image", with: @publi.image
    fill_in "Link", with: @publi.link
    fill_in "Repeat swipes", with: @publi.repeat_swipes
    fill_in "Start date", with: @publi.start_date
    fill_in "Start time", with: @publi.start_time
    fill_in "Title", with: @publi.title
    fill_in "Video", with: @publi.video
    fill_in "Weekdays", with: @publi.weekdays
    click_on "Update Publi"

    assert_text "Publi was successfully updated"
    click_on "Back"
  end

  test "destroying a Publi" do
    visit publis_url
    page.accept_confirm do
      click_on "Destroy", match: :first
    end

    assert_text "Publi was successfully destroyed"
  end
end
