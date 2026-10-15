require 'test_helper'
require_relative '../support/t03_boundary_helpers'

class ComplaintsControllerTest < ActionDispatch::IntegrationTest
  include T03BoundaryHelpers
  self.fixture_table_names = []

  setup do
    @reporter = create_boundary_user(name: 'Complaint reporter')
    @target = create_boundary_user(name: 'Reported account')
    @other = create_boundary_user(name: 'Unrelated account')
    @admin = create_boundary_user(name: 'Moderator', admin: true)
    @complaint = Complaint.create!(
      user: @reporter, reported_user: @target, reason: 'Original reason',
      reason_key: 'harassment', text: 'Private complaint evidence'
    )
  end

  test 'anonymous callers cannot read submit moderate or delete complaints' do
    assert_no_difference(['Complaint.count', 'Block.count']) do
      get complaints_url, as: :json
      assert_response :unauthorized
      get complaint_url(@complaint), as: :json
      assert_response :unauthorized
      post complaints_url, params: { complaint: submission }, as: :json
      assert_response :unauthorized
      patch complaint_url(@complaint), params: { complaint: { action_taken: 'user_blocked' } }, as: :json
      assert_response :unauthorized
      delete complaint_url(@complaint), as: :json
      assert_response :unauthorized
    end
    assert_not @target.reload.blocked?
    assert_equal 'no_action', @complaint.reload.action_taken
  end

  test 'invalid expired and revoked JWTs cannot submit a complaint' do
    [{ 'Authorization' => 'Bearer invalid-jwt' },
     authorization_for(@reporter, exp: 1.second.ago.to_i),
     authorization_for(@reporter, jti: 'revoked-test-jti')].each do |headers|
      assert_no_difference(['Complaint.count', 'Block.count']) do
        post complaints_url, params: { complaint: submission }, headers: headers, as: :json
      end
      assert_response :unauthorized
    end
  end

  test 'blocked accounts cannot submit a complaint or personal block' do
    @reporter.update!(blocked: true)
    assert_no_difference(['Complaint.count', 'Block.count']) do
      post complaints_url, params: { complaint: submission }, headers: authorization_for(@reporter), as: :json
    end
    assert_response :unauthorized
  end

  test 'mobile submission creates a complaint and personal block for the authenticated reporter' do
    assert_difference(['Complaint.count', 'Block.count'], 1) do
      post complaints_url, params: { complaint: submission }, headers: authorization_for(@reporter), as: :json
    end

    assert_response :created
    created = Complaint.find(response.parsed_body.fetch('id'))
    assert_equal @reporter.id, created.user_id
    assert_equal @target.id, created.to_user_id
    assert_equal 'harassment', created.reason_key
    assert_equal 'no_action', created.action_taken
    assert_equal 'unreviewed', created.status
    assert @reporter.blocks.exists?(blocked_user_id: @target.id)
    assert_not @target.reload.blocked?
    assert_nil @target.block_reason_key
  end

  test 'submitting without a personal block does not create one' do
    assert_difference('Complaint.count', 1) do
      assert_no_difference('Block.count') do
        post complaints_url, params: { complaint: submission.merge(block_user: false) },
             headers: authorization_for(@reporter), as: :json
      end
    end
    assert_response :created
    assert_not @target.reload.blocked?
  end

  test 'ordinary HTML submission redirects to its accessible own profile' do
    assert_difference('Complaint.count', 1) do
      post complaints_url, params: { complaint: submission }, headers: authorization_for(@reporter)
    end

    assert_redirected_to show_user_url(id: @reporter.id)
    assert_equal @reporter.id, Complaint.order(:id).last.user_id
  end

  test 'admin HTML submission retains the complaint detail redirect' do
    assert_difference('Complaint.count', 1) do
      post complaints_url, params: { complaint: submission }, headers: authorization_for(@admin)
    end

    assert_redirected_to complaint_url(Complaint.order(:id).last)
  end

  test 'repeated mobile submissions do not duplicate a personal block' do
    @reporter.blocks.create!(blocked_user: @target)
    assert_difference('Complaint.count', 1) do
      assert_no_difference('Block.count') do
        post complaints_url, params: { complaint: submission }, headers: authorization_for(@reporter), as: :json
      end
    end
    assert_response :created
  end

  test 'submission cannot forge the author or moderation outcome' do
    assert_difference('Complaint.count', 1) do
      post complaints_url, params: {
        complaint: submission.merge(user_id: @other.id, action_taken: 'user_blocked', status: 'reviewed')
      }, headers: authorization_for(@reporter), as: :json
    end

    assert_response :created
    created = Complaint.find(response.parsed_body.fetch('id'))
    assert_equal @reporter.id, created.user_id
    assert_equal 'no_action', created.action_taken
    assert_equal 'unreviewed', created.status
    assert @reporter.blocks.exists?(blocked_user_id: @target.id)
    assert_not @other.blocks.exists?(blocked_user_id: @target.id)
    assert_not @target.reload.blocked?
    assert_nil @target.block_reason_key
  end

  test 'admin submission also starts unreviewed under its authenticated author' do
    post complaints_url, params: {
      complaint: submission.merge(user_id: @reporter.id, action_taken: 'invalidated', status: 'reviewed')
    }, headers: authorization_for(@admin), as: :json

    assert_response :created
    created = Complaint.find(response.parsed_body.fetch('id'))
    assert_equal @admin.id, created.user_id
    assert_equal 'no_action', created.action_taken
    assert_equal 'unreviewed', created.status
  end

  %i[reporter target other].each do |role|
    test "#{role} cannot access the global complaint index" do
      get complaints_url, headers: authorization_for(instance_variable_get("@#{role}")), as: :json
      assert_response :forbidden
      assert_not_includes response.body, 'Private complaint evidence'
    end

    test "#{role} cannot read complaint details" do
      get complaint_url(@complaint), headers: authorization_for(instance_variable_get("@#{role}")), as: :json
      assert_response :forbidden
      assert_not_includes response.body, 'Private complaint evidence'
    end

    test "#{role} cannot moderate a complaint" do
      assert_no_difference(['Complaint.count', 'Block.count']) do
        patch complaint_url(@complaint), params: {
          complaint: { action_taken: 'user_blocked', user_id: @other.id, to_user_id: @other.id }
        }, headers: authorization_for(instance_variable_get("@#{role}")), as: :json
      end
      assert_response :forbidden
      assert_equal 'no_action', @complaint.reload.action_taken
      assert_equal @reporter.id, @complaint.user_id
      assert_equal @target.id, @complaint.to_user_id
      assert_not @target.reload.blocked?
      assert_not @other.reload.blocked?
    end

    test "#{role} cannot delete complaint evidence" do
      assert_no_difference('Complaint.count') do
        delete complaint_url(@complaint), headers: authorization_for(instance_variable_get("@#{role}")), as: :json
      end
      assert_response :forbidden
      assert Complaint.exists?(@complaint.id)
    end
  end

  test 'ordinary users cannot open administrative complaint forms in HTML' do
    with_test_pack { get new_complaint_url, headers: authorization_for(@reporter).merge('Accept' => 'text/html'), xhr: true }
    assert_response :forbidden
    with_test_pack { get edit_complaint_url(@complaint), headers: authorization_for(@reporter).merge('Accept' => 'text/html'), xhr: true }
    assert_response :forbidden
  end

  test 'ordinary complaint access is denied before looking up an unknown id' do
    get complaint_url(0), headers: authorization_for(@reporter), as: :json
    assert_response :forbidden
  end

  test 'ordinary users cannot browse global complaint evidence in HTML' do
    headers = authorization_for(@reporter).merge('Accept' => 'text/html')
    with_test_pack { get complaints_url, headers: headers, xhr: true }
    assert_response :forbidden
    assert_not_includes response.body, 'Private complaint evidence'
    with_test_pack { get complaint_url(@complaint), headers: headers, xhr: true }
    assert_response :forbidden
    assert_not_includes response.body, 'Private complaint evidence'
  end

  test 'admin can list and read complaint evidence' do
    get complaints_url, headers: authorization_for(@admin), as: :json
    assert_response :ok
    assert_equal [@complaint.id], response.parsed_body.map { |record| record.fetch('id') }

    get complaint_url(@complaint), headers: authorization_for(@admin), as: :json
    assert_response :ok
    assert_equal 'Private complaint evidence', response.parsed_body.fetch('text')
  end

  test 'admin complaint filters still select the requested evidence' do
    Complaint.create!(user: @other, reported_user: @target, reason: 'Different reason', action_taken: 'invalidated')
    get complaints_url, params: { reason: 'Original reason', status: 'unreviewed', action_taken: 'no_action' },
        headers: authorization_for(@admin), as: :json
    assert_response :ok
    assert_equal [@complaint.id], response.parsed_body.map { |record| record.fetch('id') }
  end

  test 'admin can globally block the original target without rewriting complaint evidence' do
    assert_no_difference('Block.count') do
      patch complaint_url(@complaint), params: {
        complaint: {
          action_taken: 'user_blocked', status: 'unreviewed', user_id: @other.id, to_user_id: @other.id,
          reason: 'Rewritten reason', reason_key: 'spam', text: 'Rewritten evidence', block_user: true
        }
      }, headers: authorization_for(@admin), as: :json
    end

    assert_response :ok
    assert_equal true, response.parsed_body.fetch('success')
    assert_equal 'user_blocked', @complaint.reload.action_taken
    assert_equal 'reviewed', @complaint.status
    assert_equal @reporter.id, @complaint.user_id
    assert_equal @target.id, @complaint.to_user_id
    assert_equal 'Original reason', @complaint.reason
    assert_equal 'harassment', @complaint.reason_key
    assert_equal 'Private complaint evidence', @complaint.text
    assert_not @complaint.block_user?
    assert @target.reload.blocked?
    assert_equal 'harassment', @target.block_reason_key
    assert_not @other.reload.blocked?
    assert_nil @other.block_reason_key
  end

  test 'admin can ignore a complaint without globally blocking its target' do
    patch complaint_url(@complaint), params: { complaint: { action_taken: 'invalidated' } },
          headers: authorization_for(@admin), as: :json
    assert_response :ok
    assert_equal 'invalidated', @complaint.reload.action_taken
    assert_equal 'reviewed', @complaint.status
    assert_not @target.reload.blocked?
    assert_nil @target.block_reason_key
  end

  test 'admin can ignore historical complaints whose reported account no longer exists' do
    @complaint.update!(to_user_id: nil)
    patch complaint_url(@complaint), params: { complaint: { action_taken: 'invalidated' } },
          headers: authorization_for(@admin), as: :json
    assert_response :ok
    assert_equal 'invalidated', @complaint.reload.action_taken
  end

  test 'admin cannot apply a global block when the reported account no longer exists' do
    @complaint.update!(to_user_id: nil)
    patch complaint_url(@complaint), params: { complaint: { action_taken: 'user_blocked' } },
          headers: authorization_for(@admin), as: :json
    assert_response :unprocessable_entity
    assert_equal false, response.parsed_body.fetch('success')
    assert_equal 'no_action', @complaint.reload.action_taken
  end

  test 'admin can delete complaint evidence' do
    assert_difference('Complaint.count', -1) do
      delete complaint_url(@complaint), headers: authorization_for(@admin), as: :json
    end
    assert_response :no_content
    assert_not Complaint.exists?(@complaint.id)
  end

  test 'admin HTML moderation retains its redirect contract' do
    patch complaint_url(@complaint), params: { complaint: { action_taken: 'invalidated' } },
          headers: authorization_for(@admin)
    assert_redirected_to complaints_url
    assert_equal 'invalidated', @complaint.reload.action_taken
  end

  test 'admin HTML index keeps block ignore and delete controls' do
    with_test_pack { get complaints_url, headers: authorization_for(@admin).merge('Accept' => 'text/html'), xhr: true }
    assert_response :ok
    assert_select 'input[name="complaint[action_taken]"][value="user_blocked"]'
    assert_select 'input[name="complaint[action_taken]"][value="invalidated"]'
    assert_select "a[data-method='delete'][href='#{complaint_path(@complaint)}']"
  end

  test 'admin submission form does not offer a client selected author or moderation action' do
    with_test_pack { get new_complaint_url, headers: authorization_for(@admin).merge('Accept' => 'text/html'), xhr: true }
    assert_response :ok
    assert_select 'input[name="complaint[to_user_id]"]'
    assert_select 'input[name="complaint[user_id]"]', count: 0
    assert_select 'select[name="complaint[action_taken]"], input[name="complaint[action_taken]"]', count: 0
  end

  test 'admin edit form offers moderation without editable author target or evidence' do
    with_test_pack { get edit_complaint_url(@complaint), headers: authorization_for(@admin).merge('Accept' => 'text/html'), xhr: true }
    assert_response :ok
    assert_select 'select[name="complaint[action_taken]"]' do
      assert_select 'option[value="user_blocked"]'
      assert_select 'option[value="invalidated"]'
    end
    %w[user_id to_user_id reason reason_key text block_user status].each do |field|
      assert_select "input[name='complaint[#{field}]'], textarea[name='complaint[#{field}]'], select[name='complaint[#{field}]']", count: 0
    end
    assert_includes response.body, 'Private complaint evidence'
  end

  private

  def submission
    { to_user_id: @target.id, reason: 'Mobile reason', text: 'Mobile evidence', reason_key: 'harassment', block_user: true }
  end

  def with_test_pack
    Webpacker.manifest.stub(:lookup!, '/packs-test/application.js') { yield }
  end
end
