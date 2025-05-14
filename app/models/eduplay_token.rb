class EduplayToken < ActiveRecord::Base

  def to_s
    "id=#{self.id}, user_uid=#{self.user_uid}, expires_at=#{self.expires_at}"
  end
end
