require 'test_helper'

class LikesQueriesTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  setup do
    @a = User.create!(email: 'query-a@example.com', password: 'Secure123!')
    @b = User.create!(email: 'query-b@example.com', password: 'Secure123!')
  end

  test 'match_between prefers latest outgoing then incoming' do
    first = create_request(@a, @b)
    latest = create_request(@a, @b, created_at: 1.minute.from_now)
    incoming = create_request(@b, @a)
    assert_equal latest, UserMatchRequest.match_between(@a.id, @b.id)
    first.destroy!
    latest.destroy!
    assert_equal incoming, UserMatchRequest.match_between(@a.id, @b.id)
  end

  test 'confirmed match recognizes both directions but not ordinary likes' do
    row = create_request(@a, @b)
    assert_not UserMatchRequest.match_confirmed_between?(@a.id, @b.id)
    row.update!(is_match: true)
    assert UserMatchRequest.match_confirmed_between?(@a.id, @b.id)
    assert UserMatchRequest.match_confirmed_between?(@b.id, @a.id)
  end

  test 'incoming likes excludes rejected and confirmed requests' do
    row = create_request(@b, @a)
    assert_includes @a.incoming_likes, row
    row.update!(is_rejected: true)
    assert_empty @a.incoming_likes
    row.update!(is_rejected: false, is_match: true)
    assert_empty @a.incoming_likes
  end

  test 'matches includes superlikes and removes blocked users in either direction' do
    row = create_request(@a, @b, is_superlike: true)
    assert_includes @a.matches, row
    block = Block.create!(user: @b, blocked_user: @a)
    assert_empty @a.matches
    block.destroy!
    Block.create!(user: @a, blocked_user: @b)
    assert_empty @a.matches
  end

  test 'using superlike cannot go below zero sequentially' do
    @a.update!(superlike_available: 1)
    assert @a.use_superlike
    assert_not @a.use_superlike
    assert_equal 0, @a.reload.superlike_available
  end

  test 'KNOWN BUG confirmed query counts a self-match as a match with another user' do
    create_request(@a, @a, is_match: true)
    assert UserMatchRequest.match_confirmed_between?(@a.id, @b.id)
  end

  private
  def create_request(a, b, **attrs)
    UserMatchRequest.create!({ user: a, target_user: b.id, is_like: true }.merge(attrs))
  end
end
