class RemoveOldAppLaunchJob < ApplicationJob
  def perform()
    date_limit = Rails.application.config.launch_days_to_delete.days.ago
    limit_for_delete = Rails.application.config.launch_limit_for_delete

    app_launches = qty_expired_launches(date_limit)

    while app_launches > 0
      begin
        Resque.logger.info "Removing old AppLaunches:"

        query_started = Time.now.utc
        deleted_launches = delete_launches(date_limit, limit_for_delete)
        query_duration = Time.now.utc - query_started
        Resque.logger.info "Removing the old AppLaunches from before #{date_limit}, " \
                          "#{deleted_launches} AppLaunches deleted, " \
                          "in: #{query_duration.round(3)} seconds"

        app_launches = qty_expired_launches(date_limit)
      rescue StandardError => e
        Resque.logger.error "Error removing old LtiLaunch: #{e.message}", \
        "These #{deleted_launches} have not been deleted."
      end
    end
  end

  def delete_launches(date_limit, limit_for_delete)
    launches_to_delete = <<-SQL
      DELETE FROM app_launches WHERE id IN(
      SELECT app_launches.id
      FROM app_launches
      LEFT JOIN scheduled_meetings
      ON nonce = scheduled_meetings.created_by_launch_nonce
      WHERE scheduled_meetings.created_by_launch_nonce IS NULL
      AND expires_at < '#{date_limit}'
      LIMIT '#{limit_for_delete}'
      )
    SQL

    deleted_launches = ActiveRecord::Base.connection.execute(launches_to_delete).cmd_tuples
  end

  def qty_expired_launches(date_limit)
    expired_launches = <<-SQL
      SELECT app_launches.id
      FROM app_launches
      LEFT JOIN scheduled_meetings
      ON nonce = scheduled_meetings.created_by_launch_nonce
      WHERE scheduled_meetings.created_by_launch_nonce IS NULL
      AND expires_at < '#{date_limit}'
    SQL

    quantity = ActiveRecord::Base.connection.execute(expired_launches).cmd_tuples
  end
end
