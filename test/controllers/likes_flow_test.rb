require 'test_helper'
require 'minitest/mock'

class LikesFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  self.fixture_table_names = []

  setup do
    @actor = User.create!(email: 'likes-actor@example.com', password: 'Secure123!', gender: 'male')
    @target = User.create!(email: 'likes-target@example.com', password: 'Secure123!', gender: 'male')
    @actor.update!(likes_left: 5, superlike_available: 3, next_sugar_play: 30)
    sign_in @actor
    clear_enqueued_jobs
  end

  teardown { clear_enqueued_jobs }

  test 'first like creates an outgoing request and consumes one like' do
    assert_difference('UserMatchRequest.count', 1) { swipe }
    assert_response :success
    request = UserMatchRequest.last
    assert_equal [@actor.id, @target.id], [request.user_id, request.target_user]
    assert request.is_like
    assert_not request.is_match
    assert_equal 4, @actor.reload.likes_left
    assert_enqueued_with(job: SendLikeNotificationJob, args: [request.id])
  end

  test 'dislike does not consume likes or enqueue a like notification' do
    assert_no_enqueued_jobs { swipe(is_like: false) }
    assert_response :success
    assert UserMatchRequest.last.is_rejected
    assert_equal 5, @actor.reload.likes_left
  end

  test 'reciprocal like confirms the incoming request and enqueues conversation' do
    incoming = request_from(@target, @actor)
    assert_no_difference('UserMatchRequest.count') { swipe }
    assert_response :success
    assert incoming.reload.is_match
    assert incoming.match_date
    assert_enqueued_with(job: CreateTwilioConversationJob)
    assert_enqueued_with(job: SendMatchNotificationJob, args: [incoming.id])
  end

  test 'exhausted ordinary likes return 422 without mutation' do
    @actor.update!(likes_left: 0, last_like_given: Time.current)
    assert_no_difference('UserMatchRequest.count') { swipe }
    assert_response :unprocessable_entity
    assert_equal 0, @actor.reload.likes_left
  end

  test 'exhausted superlikes reject before creating a request' do
    @actor.update!(superlike_available: 0)
    assert_no_difference('UserMatchRequest.count') { swipe(is_superlike: true) }
    assert_response :unprocessable_entity
  end

  test 'superlike consumes its own balance only' do
    swipe(is_superlike: true)
    assert_response :success
    assert UserMatchRequest.last.is_superlike
    assert_equal 2, @actor.reload.superlike_available
    assert_equal 5, @actor.likes_left
  end

  test 'reject incoming like hides it without spending balance' do
    incoming = request_from(@target, @actor)
    post '/reject_match.json', params: { user_id: @target.id }, as: :json
    assert_response :success
    assert incoming.reload.is_rejected
    assert_equal 5, @actor.reload.likes_left
  end

  test 'changing a pending like to dislike preserves one rejected decision' do
    swipe
    row = UserMatchRequest.last
    assert_no_difference('UserMatchRequest.count') { swipe(is_like: false) }
    assert_response :success
    assert_equal [false, true, false], [row.reload.is_like, row.is_rejected, row.is_match]
    assert_equal 4, @actor.reload.likes_left
  end

  test 'KNOWN BUG disliking a reciprocal match rewrites the other users like' do
    incoming = request_from(@target, @actor)
    swipe
    assert incoming.reload.is_match
    swipe(is_like: false)
    assert_response :success
    assert_not UserMatchRequest.where(user_id: @actor.id, target_user: @target.id).exists?
    assert_equal [false, true, false], [incoming.reload.is_like, incoming.is_rejected, incoming.is_match]
  end

  test 'changing an outgoing confirmed match to dislike splits the decisions' do
    original = UserMatchRequest.create!(user: @actor, target_user: @target.id,
                                        is_like: true, is_match: true)
    swipe(is_like: false)
    assert_response :success
    mine = UserMatchRequest.find_by!(user_id: @actor.id, target_user: @target.id)
    theirs = UserMatchRequest.find_by!(user_id: @target.id, target_user: @actor.id)
    assert_equal original.id, mine.id
    assert_equal [false, true, false], [mine.is_like, mine.is_rejected, mine.is_match]
    assert_equal [true, false, false], [theirs.is_like, theirs.is_rejected, theirs.is_match]
  end

  test 'repeat dislike leaves a single record and never consumes ordinary likes' do
    2.times { swipe(is_like: false) }
    assert_response :success
    assert_equal 1, UserMatchRequest.where(user_id: @actor.id, target_user: @target.id).count
    assert_equal 5, @actor.reload.likes_left
  end

  test 'KNOWN BUG disliking an incoming like rewrites the senders decision' do
    incoming = request_from(@target, @actor)
    swipe(is_like: false)
    assert_response :success
    assert_equal [false, true], [incoming.reload.is_like, incoming.is_rejected]
    assert_not UserMatchRequest.where(user_id: @actor.id, target_user: @target.id).exists?
  end

  test 'KNOWN BUG reject endpoint creates a dislike attributed to another user' do
    assert_difference('UserMatchRequest.count', 1) do
      post '/reject_match.json', params: { user_id: @target.id }, as: :json
    end
    assert_response :success
    row = UserMatchRequest.last
    assert_equal [@target.id, @actor.id, false, true],
                 [row.user_id, row.target_user, row.is_like, row.is_rejected]
  end

  test 'KNOWN BUG string boolean flags can prevent a reciprocal match' do
    incoming = request_from(@target, @actor)
    post '/send_match.json', params: {
      target_user: @target.id, is_like: 'true',
      is_superlike: 'false', is_sugar_sweet: 'false'
    }, as: :json
    assert_response :success
    assert_not incoming.reload.is_match
  end

  test 'likes list excludes matched rejected and blocked senders' do
    visible = request_from(@target, @actor)
    third = User.create!(email: 'likes-third@example.com', password: 'Secure123!')
    request_from(third, @actor)
    Block.create!(user: third, blocked_user: @actor)
    get '/get_user_likes.json'
    assert_response :success
    assert_equal [visible.id], response.parsed_body.map { |row| row['id'] }
    visible.update!(is_rejected: true)
    get '/get_user_likes.json'
    assert_empty response.parsed_body
  end

  # Characterization tests document existing defects; they are NOT desired rules.
  test 'KNOWN BUG repeated like spends balance again without another request' do
    swipe
    assert_no_difference('UserMatchRequest.count') { swipe }
    assert_equal 3, @actor.reload.likes_left
  end

  test 'KNOWN BUG dislike changed to like creates a match without reciprocation' do
    swipe(is_like: false)
    swipe
    assert UserMatchRequest.last.is_match
    assert_not UserMatchRequest.where(user_id: @target.id, target_user: @actor.id).exists?
  end

  test 'KNOWN BUG sender can swipe a blocked target' do
    Block.create!(user: @target, blocked_user: @actor)
    swipe
    assert_response :success
    assert UserMatchRequest.last.is_like
  end

  test 'KNOWN BUG self-like is accepted' do
    post '/send_match.json', params: { target_user: @actor.id, is_like: true, is_superlike: false }, as: :json
    assert_response :success
    assert_equal @actor.id, UserMatchRequest.last.target_user
  end

  test 'KNOWN BUG unrelated authenticated user can read and delete a match by ID' do
    third = User.create!(email: 'unrelated-pair@example.com', password: 'Secure123!')
    row = request_from(@target, third)
    get "/user_match_requests/#{row.id}.json"
    assert_response :success
    assert_equal row.id, response.parsed_body['id']
    delete "/user_match_requests/#{row.id}.json"
    assert_response :no_content
    assert_not UserMatchRequest.exists?(row.id)
  end

  test 'KNOWN BUG unrelated user can send first message to another pairs conversation' do
    third = User.create!(email: 'message-pair@example.com', password: 'Secure123!')
    row = request_from(@target, third)
    row.update!(is_match: true, twilio_conversation_sid: 'test-conversation')
    calls = []
    twilio = Object.new
    twilio.define_singleton_method(:send_message_to_conversation) { |*args| calls << args; true }
    TwilioController.stub(:new, twilio) do
      post '/send_first_message_to_match.json', params: { id: row.id, message: 'test message' }, as: :json
    end
    assert_response :success
    assert_equal [['test-conversation', @actor.id, 'test message']], calls
  end

  test 'unauthenticated swipe is rejected without changing requests' do
    sign_out @actor
    assert_no_difference('UserMatchRequest.count') { swipe }
    assert_response :unauthorized
  end

  private

  def swipe(**overrides)
    post '/send_match.json', params: { target_user: @target.id, is_like: true,
                                     is_superlike: false, is_sugar_sweet: false }.merge(overrides), as: :json
  end

  def request_from(sender, receiver)
    UserMatchRequest.create!(user: sender, target_user: receiver.id, is_like: true)
  end
end
