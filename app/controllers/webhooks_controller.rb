# frozen_string_literal: true

class WebhooksController < ActionController::Base

  def moodle_attendance
    json_body = request.body.read

    if json_body.blank?
      render json: { error: 'Request body is empty' }, status: :bad_request
      return
    end

     # Enqueue the job for background processing
    begin
      MoodleAttendanceJob.perform_later(json_body)
      Rails.logger.info "WebhooksController: MoodleAttendanceJob enqueued. IDs will be derived from JSON body."
      head :accepted # HTTP 202 Accepted: Request accepted for processing
    rescue StandardError => e
      Rails.logger.error "WebhooksController: Failed to enqueue MoodleAttendanceJob. Error: #{e.class} - #{e.message}"
      render json: { error: 'Failed to process webhook' }, status: :internal_server_error
    end
  end
end
