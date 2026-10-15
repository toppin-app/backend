require 'test_helper'
require 'minitest/mock'
require 'timeout'

class PasswordRecoveryConcurrencyTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []
  self.use_transactional_tests = false

  setup do
    @owner = User.create!(email: "reset-race-#{SecureRandom.hex(6)}@example.com", password: 'Original123!')
    @token = SecureRandom.urlsafe_base64(32)
    @recovery = PasswordRecovery.create!(email: @owner.email, recovery_code: '123456',
                                        expires_at: 10.minutes.from_now, verified: true, attempts: 1,
                                        reset_token_digest: Digest::SHA256.hexdigest(@token))
  end

  teardown do
    PasswordRecovery.for_email(@owner.email).delete_all
    UserFilterPreference.where(user_id: @owner.id).delete_all
    User.where(id: @owner.id).delete_all
  end

  [:token, :legacy].each do |proof|
    test "two concurrent #{proof} resets consume a single capability" do
      params = { email: @owner.email, new_password: 'Replacement123!' }
      params.merge!(proof == :token ? { recovery_token: @token } : { code: '123456' })
      statuses = while_row_is_locked(@owner, 2) do
        client = ActionDispatch::Integration::Session.new(Rails.application)
        client.post '/password_recoveries/reset_password', params: params, as: :json
        client.response.status
      end
      assert_equal [200, 403], statuses.sort
      assert @owner.reload.valid_password?('Replacement123!')
      assert_equal 0, PasswordRecovery.for_email(@owner.email).count
    end
  end

  test 'concurrent wrong reset proofs cannot exceed the five attempt budget' do
    statuses = while_row_is_locked(@owner, 6) do
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.post '/password_recoveries/reset_password', params: {
        email: @owner.email, code: '000000', new_password: 'Replacement123!'
      }, as: :json
      client.response.status
    end
    assert_equal [403] * 6, statuses
    assert_equal 5, @recovery.reload.reset_attempts
    assert @owner.reload.valid_password?('Original123!')
    post '/password_recoveries/reset_password', params: {
      email: @owner.email, recovery_token: @token, new_password: 'Replacement123!'
    }, as: :json
    assert_response :forbidden
  end

  test 'concurrent wrong verification codes cannot exceed the five attempt budget' do
    @recovery.update!(verified: false, attempts: 0, reset_token_digest: nil)
    statuses = while_row_is_locked(@recovery, 6) do
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.post '/password_recoveries/verify_code', params: { email: @owner.email, code: '000000' }, as: :json
      client.response.status
    end
    assert_equal [400] * 6, statuses
    assert_equal 5, @recovery.reload.attempts
    assert_not @recovery.verified?
  end

  test 'a new recovery concurrent with reset cannot leave an old proof reusable' do
    @recovery.update_columns(created_at: 2.minutes.ago)
    statuses = Mailjet::Send.stub(:create, ->(**) { Object.new }) do
      while_row_is_locked(@owner, 2) do |index|
        client = ActionDispatch::Integration::Session.new(Rails.application)
        if index.zero?
          client.post '/password_recoveries/request_code', params: { email: @owner.email }, as: :json
        else
          client.post '/password_recoveries/reset_password', params: {
            email: @owner.email, recovery_token: @token, new_password: 'Replacement123!'
          }, as: :json
        end
        client.response.status
      end
    end
    assert_equal 200, statuses.first
    assert_includes [200, 403], statuses.last
    expected_password = statuses.last == 200 ? 'Replacement123!' : 'Original123!'
    assert @owner.reload.valid_password?(expected_password)
    newest = PasswordRecovery.for_email(@owner.email).order(created_at: :desc, id: :desc).first
    assert_not newest.verified?
    assert_nil newest.reset_token_digest
    post '/password_recoveries/reset_password', params: {
      email: @owner.email, recovery_token: @token, new_password: 'Another123!'
    }, as: :json
    assert_response :forbidden
    assert @owner.reload.valid_password?(expected_password)
  end

  # Insert a barrier immediately before real locking SQL; no transaction or
  # persistence is replaced. Requests hold distinct verified MySQL connections.
  def while_row_is_locked(record, workers, &request)
    ready = Queue.new
    threads = []
    owner_id = ActiveRecord::Base.connection.select_value('SELECT CONNECTION_ID()')
    record.with_lock do
      threads = workers.times.map do |index|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            announced = false
            announce = lambda do |sql|
              if !announced && ((sql.include?('`users`') && sql.include?('FOR UPDATE')) ||
                                sql.start_with?('UPDATE `users`') || sql.start_with?('UPDATE `password_recoveries`'))
                announced = true
                ready << connection.select_value('SELECT CONNECTION_ID()')
              end
            end
            query = connection.method(:exec_query)
            update = connection.method(:exec_update)
            connection.stub(:exec_query, lambda { |sql, *args|
              keywords = args.last.is_a?(Hash) ? args.pop : {}
              announce.call(sql)
              query.call(sql, *args, **keywords)
            }) do
              connection.stub(:exec_update, ->(sql, *args) { announce.call(sql); update.call(sql, *args) }) do
                result = request.call(index)
                ready << [:unobserved, result] unless announced
                result
              end
            end
          end
        end
      end
      workers.times do
        worker_id = Timeout.timeout(10) { ready.pop }
        flunk("Request finished before its lock barrier: #{worker_id.last}") if worker_id.is_a?(Array)
        assert_not_equal owner_id, worker_id
      end
    end
    threads.map { |thread| Timeout.timeout(15) { thread.value } }
  ensure
    threads.each { |thread| thread.kill if thread.alive? }
  end
end
