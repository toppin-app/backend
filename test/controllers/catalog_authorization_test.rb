require 'test_helper'
require 'minitest/mock'

class CatalogAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  self.fixture_table_names = []

  CATALOGS = [
    { resource: 'interests', model: Interest, parameter: :interest, attribute: :name },
    { resource: 'info_item_categories', model: InfoItemCategory, parameter: :info_item_category, attribute: :name },
    { resource: 'info_item_values', model: InfoItemValue, parameter: :info_item_value, attribute: :name },
    { resource: 'publis', model: Publi, parameter: :publi, attribute: :title }
  ].freeze

  setup do
    @regular_user = User.create!(email: 'catalog-reader@example.com', password: 'Secure123!', name: 'Catalog reader')
    @admin = User.create!(email: 'catalog-admin@example.com', password: 'Secure123!', name: 'Catalog admin', admin: true)
    category = InfoItemCategory.create!(name: 'Profile category')
    @catalog_records = {
      'interests' => Interest.create!(name: 'Outdoor interest'),
      'info_item_categories' => category,
      'info_item_values' => InfoItemValue.create!(name: 'Profile value', info_item_category: category),
      'publis' => Publi.create!(title: 'Campaign', weekdays: '1,2', start_date: 1.day.ago, end_date: 1.day.from_now)
    }
    @app_version = AppVersions.create!(
      android_last_version: '1.2.0', android_last_version_required: '1.0.0',
      ios_last_version: '2.2.0', ios_last_version_required: '2.0.0',
      android_store_link: 'https://play.google.com/store/apps/details?id=test.toppin',
      ios_store_link: 'https://apps.apple.com/app/id123456'
    )
  end

  CATALOGS.each do |catalog|
    [:new, :edit, :create, :patch, :put, :destroy].each do |action|
      [:anonymous, :regular].each do |identity|
        test "#{identity} cannot #{action} #{catalog[:resource]}" do
          sign_in @regular_user if identity == :regular
          record = @catalog_records.fetch(catalog[:resource])
          original_attributes = record.attributes

          assert_no_difference("#{catalog[:model].name}.count") do
            request_catalog_action(catalog, action, value: 'Unauthorized change')
          end

          assert_equal original_attributes, record.reload.attributes
          if identity == :regular
            assert_redirected_to root_path
          elsif [:new, :edit].include?(action)
            assert_redirected_to new_user_session_path
          else
            assert_response :unauthorized
          end
        end
      end
    end

    [:new, :edit].each do |action|
      test "admin can open #{catalog[:resource]} #{action} form" do
        sign_in @admin

        request_catalog_action(catalog, action)

        assert_response :success
      end
    end

    test "admin can create #{catalog[:resource]}" do
      sign_in @admin

      assert_difference("#{catalog[:model].name}.count", 1) do
        request_catalog_action(catalog, :create, value: 'Created by admin')
      end

      assert_response :created
      assert_equal 'Created by admin', catalog[:model].unscoped.order(:id).last.public_send(catalog[:attribute])
    end

    [:patch, :put].each do |verb|
      test "admin can update #{catalog[:resource]} using #{verb}" do
        sign_in @admin

        request_catalog_action(catalog, verb, value: 'Updated by admin')

        assert_response :success
        assert_equal 'Updated by admin', @catalog_records.fetch(catalog[:resource]).reload.public_send(catalog[:attribute])
      end
    end

    test "admin can destroy #{catalog[:resource]}" do
      sign_in @admin
      record = @catalog_records.fetch(catalog[:resource])

      assert_difference("#{catalog[:model].name}.count", -1) do
        request_catalog_action(catalog, :destroy)
      end

      assert_response :no_content
      assert_not catalog[:model].exists?(record.id)
    end

    [:index, :show].each do |action|
      test "regular user can still read #{catalog[:resource]} #{action}" do
        sign_in @regular_user
        record = @catalog_records.fetch(catalog[:resource])
        path = action == :index ? "/#{catalog[:resource]}.json" : "/#{catalog[:resource]}/#{record.id}.json"

        get path

        assert_response :success
        result = action == :index ? response.parsed_body.find { |item| item['id'] == record.id } : response.parsed_body
        assert_equal record.public_send(catalog[:attribute]), result.fetch(catalog[:attribute].to_s)
      end
    end
  end

  test 'anonymous user can still read registration interests' do
    get '/interests.json'

    assert_response :success
    assert_equal ['Outdoor interest'], response.parsed_body.map { |interest| interest.fetch('name') }
  end

  ['info_item_categories', 'info_item_values', 'publis'].each do |resource|
    test "anonymous user still needs authentication to read #{resource}" do
      get "/#{resource}.json"

      assert_response :unauthorized
    end
  end

  [:get, :post].each do |verb|
    test "anonymous app startup can still read version with #{verb}" do
      original_attributes = @app_version.attributes

      public_send verb, '/app_version', as: :json

      assert_response :success
      assert_equal({
        'android_last_version' => '1.2.0',
        'android_last_version_required' => '1.0.0',
        'ios_last_version' => '2.2.0',
        'ios_last_version_required' => '2.0.0',
        'android_store_link' => 'https://play.google.com/store/apps/details?id=test.toppin',
        'ios_store_link' => 'https://apps.apple.com/app/id123456'
      }, response.parsed_body)
      assert_equal original_attributes, @app_version.reload.attributes
    end
  end

  [:index, :edit, :patch, :put].each do |action|
    [:anonymous, :regular].each do |identity|
      test "#{identity} cannot access app versions #{action}" do
        sign_in @regular_user if identity == :regular
        original_attributes = @app_version.attributes

        request_app_version_action(action)

        assert_equal original_attributes, @app_version.reload.attributes
        assert_redirected_to(identity == :regular ? root_path : new_user_session_path)
      end
    end
  end

  test 'admin can read version management form' do
    sign_in @admin

    with_test_pack { get '/app_versions' }

    assert_response :success
    assert_select 'form[action=?]', app_version_path(@app_version), count: 2
  end

  [:patch, :put].each do |verb|
    test "admin can update app versions using #{verb}" do
      sign_in @admin

      request_app_version_action(verb)

      assert_redirected_to app_versions_path
      assert_equal '9.0.0', @app_version.reload.android_last_version_required
    end
  end

  private

  def request_catalog_action(catalog, action, value: 'New value')
    resource = catalog[:resource]
    record = @catalog_records.fetch(resource)
    attributes = { catalog[:attribute] => value }
    attributes[:info_item_category_id] = @catalog_records.fetch('info_item_categories').id if resource == 'info_item_values'
    attributes[:weekdays] = ['1', '2'] if resource == 'publis'
    params = { catalog[:parameter] => attributes }

    case action
    when :new
      with_test_pack { get "/#{resource}/new" }
    when :edit
      with_test_pack { get "/#{resource}/#{record.id}/edit" }
    when :create
      post "/#{resource}.json", params: params, as: :json
    when :patch, :put
      public_send action, "/#{resource}/#{record.id}.json", params: params, as: :json
    when :destroy
      delete "/#{resource}/#{record.id}.json", as: :json
    end
  end

  def request_app_version_action(action)
    case action
    when :index
      with_test_pack { get '/app_versions' }
    when :edit
      with_test_pack { get "/app_versions/#{@app_version.id}/edit" }
    when :patch, :put
      public_send action, "/app_versions/#{@app_version.id}", params: {
        app_version: { android_last_version_required: '9.0.0' }
      }
    end
  end

  def with_test_pack
    # Integration requests render HTML without executing compiled browser assets.
    Webpacker.manifest.stub(:lookup!, '/packs-test/application.js') { yield }
  end
end
