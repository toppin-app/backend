require 'test_helper'
require 'minitest/mock'

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    UserMainInterest.delete_all
    PhoneVerification.delete_all
    UserFilterPreference.delete_all
    User.delete_all
    Interest.delete_all
    ActiveRecord::Base.connection.execute('DELETE FROM interest_categories')
  end

  test 'signup refuses a phone that has not been verified' do
    assert_no_difference('User.count') do
      post '/signup.json', params: valid_signup_params, as: :json
    end

    assert_response :forbidden
    assert_equal 'PHONE_NOT_VERIFIED', response.parsed_body['code']
  end

  test 'signup rolls the user back when gender preferences are invalid' do
    verify_phone
    params = valid_signup_params
    params[:user][:gender_filter] = ['female', 'unsupported']

    assert_no_difference('User.count') do
      post_with_external_services_stubbed(params)
    end

    assert_response :unprocessable_entity
    assert_match(/géneros seleccionados/, response.parsed_body['error'])
  end

  test 'signup rejects an empty main-interest selection' do
    verify_phone
    params = valid_signup_params
    params[:user][:user_main_interests] = []

    post_with_external_services_stubbed(params)

    assert_response :unprocessable_entity
    assert_equal(
      'user_main_interests no puede estar vacío',
      response.parsed_body['error']
    )
  end

  test 'signup persists a complete verified registration and its interests' do
    verify_phone
    interests = create_interests(4)
    params = valid_signup_params
    params[:user][:user_main_interests] = interests.map do |interest|
      {
        interest_id: interest.id,
        name: interest.name,
        percentage: 25
      }
    end

    assert_difference('User.count', 1) do
      assert_difference('UserMainInterest.count', 4) do
        post_with_external_services_stubbed(params)
      end
    end

    assert_response :success
    user = User.find_by!(email: 'registration@example.com')
    assert_equal '+34612345678', user.phone
    assert_equal 'female', user.gender
    assert_equal 20, user.superlike_available
    assert_equal %w[male non_binary], user.user_filter_preference.gender_preferences_array
    assert_equal [25, 25, 25, 25], user.user_main_interests.order(:interest_id).pluck(:percentage)
  end

  private

  def valid_signup_params
    {
      user: {
        name: 'Registration User',
        email: 'registration@example.com',
        password: 'Secure123!',
        password_confirmation: 'Secure123!',
        gender: 'female',
        birthday: '1990-12-10',
        phone: '+34612345678',
        push_token: 'test-push-token',
        device_id: 'ABCDEF12-3456-7890-ABCD-EF1234567890',
        lat: '0.00',
        lng: '0.00',
        language: 'IT',
        gender_filter: %w[male non_binary],
        user_main_interests: [
          { interest_id: 1, name: 'Music', percentage: 25 }
        ]
      }
    }
  end

  def verify_phone
    PhoneVerification.create!(
      phone_number: '+34612345678',
      verification_code: '123456',
      verified: true,
      expires_at: 10.minutes.from_now,
      attempts: 1
    )
  end

  def create_interests(count)
    now = Time.current
    connection = ActiveRecord::Base.connection
    connection.execute(
      <<~SQL.squish
        INSERT INTO interest_categories (name, created_at, updated_at)
        VALUES (#{connection.quote('Registration')}, #{connection.quote(now)}, #{connection.quote(now)})
      SQL
    )
    category_id = connection.select_value('SELECT MAX(id) FROM interest_categories')

    count.times.map do |index|
      Interest.create!(
        interest_category_id: category_id,
        name: "Interest #{index + 1}"
      )
    end
  end

  def post_with_external_services_stubbed(params)
    twilio = Object.new
    twilio.define_singleton_method(:generate_user_in_twilio) { |_user_id| true }
    twilio.define_singleton_method(:generate_team_toppin) { |_user_id| true }

    delivery = Object.new
    delivery.define_singleton_method(:deliver_now) { true }

    TwilioController.stub(:new, twilio) do
      WelcomeMailer.stub(:welcome_email, delivery) do
        post '/signup.json', params: params, as: :json
      end
    end
  end
end
