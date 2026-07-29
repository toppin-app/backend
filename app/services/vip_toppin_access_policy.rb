class VipToppinAccessPolicy
  def initialize(user)
    @user = user
  end

  def unlimited_access?
    @user&.premium_or_supreme? || false
  end

  def unlock(target_id)
    return unless unlimited_access?

    @user.user_vip_unlocks.find_or_create_by(target_id: target_id)
  end
end
