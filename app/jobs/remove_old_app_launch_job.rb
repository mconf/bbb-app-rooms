class RemoveOldAppLaunchJob < ApplicationJob
  def perform()
    Resque.logger.info "Removing old AppLaunches"
    date_limit = Rails.configuration.launch_days_to_delete.days.ago
    limit_for_delete = Rails.configuration.launch_limit_for_delete
    query_started = Time.now.utc
    get_delete_launches = <<-SQL
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
    deleted_launches = connection.execute(get_delete_launches).cmd_tuples
    query_duration = Time.now.utc - query_started
    Resque.logger.info "Removing the old AppLaunches from before #{date_limit}, " \
                      "#{deleted_launches} AppLaunches deleted, " \
                      "in: #{query_duration.round(3)} seconds"
  end
end
