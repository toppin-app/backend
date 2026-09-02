require 'test_helper'

class UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  self.fixture_table_names = []

  setup do
    @user = create_user('profile-owner@example.com', name: 'Profile owner')
    @other_user = create_user('other-user@example.com', name: 'Other user')
    @admin = create_user('admin@example.com', name: 'Admin', admin: true)
  end

  test 'regular user can update their own profile fields' do
    sign_in @user

    put "/users/#{@user.id}.json", params: {
      user: {
        id: @user.id,
        name: 'Updated profile',
        description: 'Updated description'
      }
    }, as: :json

    assert_response :success
    assert_equal 'Updated profile', @user.reload.name
    assert_equal 'Updated description', @user.description
  end

  test 'mobile shaped payload can still update the current profile' do
    sign_in @user

    put "/users/#{@user.id}.json", params: {
      id: @user.id,
      name: 'Updated from mobile',
      description: 'Mobile payload',
      admin: true
    }, as: :json

    assert_response :success
    assert_equal 'Updated from mobile', @user.reload.name
    assert_equal 'Mobile payload', @user.description
    assert_not @user.admin?
  end

  test 'regular user cannot update another account' do
    sign_in @user

    put "/users/#{@other_user.id}.json", params: {
      user: { name: 'Unauthorized change' }
    }, as: :json

    assert_response :forbidden
    assert_equal 'Other user', @other_user.reload.name
  end

  test 'regular user cannot update another account through the admin form route' do
    sign_in @user

    post update_user_path(format: :json), params: {
      user: {
        id: @other_user.id,
        name: 'Unauthorized admin-form change'
      }
    }, as: :json

    assert_response :forbidden
    assert_equal 'Other user', @other_user.reload.name
  end

  test 'regular user cannot change privileged account fields' do
    sign_in @user

    put "/users/#{@user.id}.json", params: {
      user: {
        name: 'Safe profile change',
        admin: true,
        blocked: true,
        verified: true,
        fake_user: true,
        current_subscription_id: 'attacker-controlled',
        current_subscription_name: 'supreme'
      }
    }, as: :json

    assert_response :success

    @user.reload
    assert_equal 'Safe profile change', @user.name
    assert_not @user.admin?
    assert_not @user.blocked?
    assert_not @user.verified?
    assert_not @user.fake_user?
    assert_nil @user.current_subscription_id
    assert_nil @user.current_subscription_name
  end

  test 'admin can update another account and privileged fields' do
    sign_in @admin

    post update_user_path(format: :json), params: {
      user: {
        id: @other_user.id,
        name: 'Updated by admin',
        verified: true
      }
    }, as: :json

    assert_response :success
    assert_equal 'Updated by admin', @other_user.reload.name
    assert @other_user.verified?
  end

  test 'regular user cannot physically destroy an account' do
    sign_in @user

    assert_no_difference('User.count') do
      delete destroy_user_path(id: @other_user.id, format: :json)
    end

    assert_redirected_to root_path
    assert User.exists?(@other_user.id)
  end

  test 'admin can physically destroy an account' do
    sign_in @admin

    assert_difference('User.count', -1) do
      delete destroy_user_path(id: @other_user.id, format: :json)
    end

    assert_response :success
    assert_not User.exists?(@other_user.id)
  end

  test 'regular user can still soft delete their own account' do
    sign_in @user

    assert_no_difference('User.count') do
      post '/delete_account.json', as: :json
    end

    assert_response :success
    assert @user.reload.deleted_account?
    assert_not @other_user.reload.deleted_account?
  end

  test 'regular user cannot create accounts through the admin endpoint' do
    sign_in @user

    assert_no_difference('User.count') do
      post create_user_path, params: {
        user: {
          email: 'unauthorized-admin@example.com',
          password: 'Secure123!',
          password_confirmation: 'Secure123!',
          admin: true
        }
      }
    end

    assert_redirected_to root_path
    assert_not User.exists?(email: 'unauthorized-admin@example.com')
  end

  private

  def create_user(email, attributes = {})
    User.create!({
      email: email,
      password: 'Secure123!',
      password_confirmation: 'Secure123!'
    }.merge(attributes))
  end
end
