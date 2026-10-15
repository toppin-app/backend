require 'test_helper'
require_relative '../../support/t03_boundary_helpers'

class UsersComplaintPrivacyTest < ActionDispatch::IntegrationTest
  include T03BoundaryHelpers
  self.fixture_table_names = []

  setup do
    @reporter = create_boundary_user(name: 'Confidential reporter sentinel', birthday: Date.new(1995, 1, 1))
    @target = create_boundary_user(name: 'Reported profile', birthday: Date.new(1995, 1, 1))
    @admin = create_boundary_user(name: 'Moderator', admin: true, birthday: Date.new(1995, 1, 1))
    Complaint.create!(user: @reporter, reported_user: @target, reason: 'Confidential complaint sentinel', reason_key: 'spam')
  end

  test 'reported user profile HTML does not disclose received complaints or reporter identities' do
    with_test_pack do
      with_chat_provider_boundary do
        get show_user_path(id: @target.id), headers: authorization_for(@target).merge('Accept' => 'text/html'), xhr: true
      end
    end
    assert_response :ok
    assert_select '#complaints-received-container', count: 0
    assert_select "a[href='#{show_user_path(id: @reporter.id)}']", count: 0
    assert_not_includes response.body, 'Confidential complaint sentinel'
  end

  test 'reported user cannot request received complaint pagination through AJAX' do
    with_chat_provider_boundary do
      get show_user_path(id: @target.id, format: :js), params: { complaints_received_page: 1 },
          headers: authorization_for(@target), xhr: true
    end
    assert_response :forbidden
    assert_not_includes response.body, 'Confidential reporter sentinel'
    assert_not_includes response.body, 'Confidential complaint sentinel'
  end

  test 'reporter keeps its own submitted complaint history in HTML' do
    with_test_pack do
      with_chat_provider_boundary do
        get show_user_path(id: @reporter.id), headers: authorization_for(@reporter).merge('Accept' => 'text/html'), xhr: true
      end
    end
    assert_response :ok
    assert_select '#complaints-made-container', count: 1
    assert_includes response.body, 'Confidential complaint sentinel'
    assert_select '#complaints-received-container', count: 0
  end

  test 'reporter keeps its own submitted complaint history in AJAX' do
    with_chat_provider_boundary do
      get show_user_path(id: @reporter.id, format: :js), params: { complaints_made_page: 1 },
          headers: authorization_for(@reporter), xhr: true
    end
    assert_response :ok
    assert_includes response.body, 'Confidential complaint sentinel'
  end

  test 'reported user cannot bypass AJAX protection with another profile id' do
    with_chat_provider_boundary do
      get show_user_path(id: @reporter.id, format: :js), params: { complaints_received_page: 1 },
          headers: authorization_for(@target), xhr: true
    end
    assert_response :forbidden
    assert_not_includes response.body, 'Confidential reporter sentinel'
  end

  test 'reported user cannot bypass AJAX protection with a blank pagination value' do
    with_chat_provider_boundary do
      get show_user_path(id: @target.id, format: :js), params: { complaints_received_page: '' },
          headers: authorization_for(@target), xhr: true
    end
    assert_response :forbidden
    assert_not_includes response.body, 'Confidential reporter sentinel'
  end

  test 'admin profile HTML retains received complaint evidence' do
    with_test_pack do
      with_chat_provider_boundary do
        get show_user_path(id: @target.id), headers: authorization_for(@admin).merge('Accept' => 'text/html'), xhr: true
      end
    end
    assert_response :ok
    assert_select '#complaints-received-container', count: 1
    assert_includes response.body, 'Confidential reporter sentinel'
    assert_includes response.body, 'Confidential complaint sentinel'
  end

  test 'admin can paginate received complaint evidence through AJAX' do
    with_chat_provider_boundary do
      get show_user_path(id: @target.id, format: :js), params: { complaints_received_page: 1 },
          headers: authorization_for(@admin), xhr: true
    end
    assert_response :ok
    assert_includes response.body, 'Confidential reporter sentinel'
    assert_includes response.body, 'Confidential complaint sentinel'
  end

  test 'ordinary JSON profile access keeps its current account contract' do
    with_chat_provider_boundary do
      get show_user_path(id: @reporter.id, format: :json), headers: authorization_for(@target), as: :json
    end
    assert_response :ok
    assert_equal @target.id, response.parsed_body.fetch('id')
    assert_not response.parsed_body.key?('received_complaints')
  end

  private

  # User profile rendering constructs a chat token but must never reach Twilio.
  # Keep controller behavior, JWT authentication and complaint queries real.
  def with_chat_provider_boundary
    token = Struct.new(:to_jwt).new('synthetic-profile-chat-token')
    Twilio::REST::Client.stub(:new, Object.new) do
      Twilio::JWT::AccessToken.stub(:new, token) { yield }
    end
  end

  def with_test_pack
    Webpacker.manifest.stub(:lookup!, '/packs-test/application.js') { yield }
  end
end
