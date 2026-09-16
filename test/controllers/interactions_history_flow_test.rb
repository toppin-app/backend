require 'test_helper'

class InteractionsHistoryFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  self.fixture_table_names = []

  setup do
    @actor = User.create!(email: 'history-actor@example.com', password: 'Secure123!')
    @targets = 5.times.map do |i|
      User.create!(email: "history-target-#{i}@example.com", password: 'Secure123!')
    end
    sign_in @actor
  end

  def interaction(target, like:, **attributes)
    UserMatchRequest.create!({
      user: @actor, target_user: target.id,
      is_like: like, is_rejected: !like
    }.merge(attributes))
  end

  def reverse(target, like:)
    UserMatchRequest.create!(user: target, target_user: @actor.id,
                             is_like: like, is_rejected: !like)
  end

  def history(**params)
    get '/user_interactions', params: params
    assert_response :success
    response.parsed_body
  end

  test 'history and counters classify pending matched rejected mutual and missed decisions' do
    pending_like = interaction(@targets[0], like: true)
    matched = interaction(@targets[1], like: true, is_match: true)
    missed_like = interaction(@targets[2], like: true)
    reverse(@targets[2], like: false)
    missed_dislike = interaction(@targets[3], like: false)
    reverse(@targets[3], like: true)
    mutual_dislike = interaction(@targets[4], like: false)
    reverse(@targets[4], like: false)

    body = history
    assert_equal 5, body['pagination']['total_count']
    assert_equal({
      pending_like.id => 'pending', matched.id => 'matched',
      missed_like.id => 'not_reciprocated',
      missed_dislike.id => 'lost_opportunity',
      mutual_dislike.id => 'mutual'
    }, body['data'].index_by { |row| row['id'] }.transform_values { |row| row['status'] })

    get '/user_interactions_stats'
    assert_response :success
    stats = response.parsed_body
    assert_equal({ 'total' => 3, 'matched' => 1, 'pending' => 1, 'not_reciprocated' => 1 }, stats['likes'])
    assert_equal({ 'total' => 2, 'lost_opportunity' => 1, 'pending' => 0, 'mutual' => 1 }, stats['dislikes'])
  end

  test 'combined type and status filters include only relevant decisions' do
    pending_like = interaction(@targets[0], like: true)
    pending_dislike = interaction(@targets[1], like: false)
    matched = interaction(@targets[2], like: true, is_match: true)

    assert_equal [pending_like.id], history(type: ['likes'], status: ['pending'])['data'].map { |row| row['id'] }
    assert_equal [pending_dislike.id], history(type: ['dislikes'], status: ['pending'])['data'].map { |row| row['id'] }
    assert_equal [pending_like.id, pending_dislike.id].sort,
                 history(type: ['likes', 'dislikes'], status: ['pending'])['data'].map { |row| row['id'] }.sort
    assert_equal [matched.id], history(type: ['likes'], status: ['matched'])['data'].map { |row| row['id'] }
    assert_empty history(type: ['dislikes'], status: ['matched'])['data']
  end

  test 'pagination returns correct user rows and count without exposing another account' do
    rows = @targets.first(3).map { |target| interaction(target, like: true) }
    outsider = User.create!(email: 'history-outsider@example.com', password: 'Secure123!')
    UserMatchRequest.create!(user: outsider, target_user: @targets[4].id, is_like: true)

    first = history(page: 1, per_page: 2)
    second = history(page: 2, per_page: 2)
    assert_equal 3, first['pagination']['total_count']
    assert_equal 2, first['pagination']['total_pages']
    assert_equal 2, first['data'].size
    assert_equal [rows.first.id], second['data'].map { |row| row['id'] }
    assert_equal @targets[0].id, second['data'].first.dig('user', 'id')
  end

  test 'history and counters require authentication' do
    sign_out @actor
    get '/user_interactions'
    assert_response :redirect
    get '/user_interactions_stats'
    assert_response :redirect
  end

  test 'KNOWN BUG blocked targets remain visible in interaction history' do
    row = interaction(@targets[0], like: true)
    Block.create!(user: @targets[0], blocked_user: @actor)
    assert_equal [row.id], history['data'].map { |item| item['id'] }
  end

  test 'KNOWN BUG unlimited page size is accepted' do
    interaction(@targets[0], like: true)
    assert_equal 100_000, history(per_page: 100_000)['pagination']['per_page']
  end
end
