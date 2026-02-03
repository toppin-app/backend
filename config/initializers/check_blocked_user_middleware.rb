# Load and configure the CheckBlockedUser middleware
require_relative '../../app/middleware/check_blocked_user'

Rails.application.config.middleware.use CheckBlockedUser
