require 'minitest/mock'

# Only SDK entry points are replaced. Authentication, callbacks and persistence
# remain real; these helpers must never make provider requests.
module T03BoundaryHelpers
  def create_boundary_user(**attributes)
    User.create!({
      email: "boundary-#{SecureRandom.hex(6)}@example.com",
      password: 'Original123!', password_confirmation: 'Original123!'
    }.merge(attributes))
  end

  def authorization_for(user, **claims)
    payload = {
      'sub' => user.id.to_s, 'jti' => user.jti, 'scp' => 'user',
      'iat' => Time.current.to_i, 'exp' => 1.hour.from_now.to_i
    }.merge(claims.transform_keys(&:to_s))
    { 'Authorization' => "Bearer #{JWT.encode(payload, Warden::JWTAuth.config.secret, 'HS256')}" }
  end

  def with_test_environment(values)
    previous = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
