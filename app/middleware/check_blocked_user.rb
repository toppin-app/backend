class CheckBlockedUser
  def initialize(app)
    @app = app
  end

  def call(env)
    warden = env['warden']
    
    if warden && warden.user && warden.user.blocked && !warden.user.admin?
      warden.logout
      
      # Para peticiones JSON, devolver error JSON
      if env['HTTP_ACCEPT']&.include?('application/json') || env['CONTENT_TYPE']&.include?('application/json')
        return [
          401,
          { 'Content-Type' => 'application/json' },
          [{ error: 'Tu cuenta ha sido bloqueada. Contacta con soporte.', blocked: true }.to_json]
        ]
      else
        # Para peticiones web, redirigir a login
        return [
          302,
          { 'Location' => '/users/sign_in', 'Content-Type' => 'text/html' },
          ['Redirecting...']
        ]
      end
    end
    
    @app.call(env)
  end
end
