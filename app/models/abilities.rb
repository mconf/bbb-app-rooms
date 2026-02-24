class Abilities

  # This is a simplified authorization mechanism
  # TODO: verifiy the resource as well
  def self.can?(user, action, resource)
    case action
    when :show
      true
    when :edit
      user.present? && self.full_permission?(user)
    when :admin
      user.present? && user.admin?
    when :download_presentation_video
      # `resource` is a `Room`
      # by default every signed in user can download, unless explicitly set not to
      config = ConsumerConfig.select(:download_presentation_video).
                 find_by(key: resource&.consumer_key)
      if resource.present? && config.present? && !config.download_presentation_video?
        user.present? && self.full_permission?(user)
      else
        user.present?
      end
    when :download_artifacts
      user.present? && self.full_permission?(user)
    when :create_scheduled_meeting
      user.present? && (self.full_permission?(user) || self.allow_student_scheduling?(resource))
    when :manage_scheduled_meeting
      user.present? && (self.full_permission?(user) || self.user_created_meeting?(user, resource))
    else
      false
    end
  end

  def self.full_permission?(user)
    user.admin? || user.moderator?(self.moderator_roles)
  end

  def self.moderator_roles
    Rails.configuration.bigbluebutton_moderator_roles.split(',')
  end

  def self.allow_student_scheduling?(resource)
    return false if resource.blank?

    config = ConsumerConfig.select(:allow_student_scheduling).find_by(key: resource.consumer_key)
    config.present? && config.allow_student_scheduling?
  end

  def self.user_created_meeting?(user, resource)
    return false if resource.blank? || user.blank?

    nonce = resource.created_by_launch_nonce
    return false if nonce.blank?

    app_launch = if resource.association(:creator_launch).loaded?
                   resource.creator_launch
                 else
                   AppLaunch.select(:params).find_by(nonce: nonce)
                 end
    return false if app_launch.blank?

    creator_uid = app_launch.params&.[]('user_id')
    creator_uid.present? && creator_uid == user.uid
  end
end
