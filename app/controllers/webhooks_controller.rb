# frozen_string_literal: true
include ApplicationHelper

class WebhooksController < ApplicationController
  def moodle_attendance
    set_current_locale
    json_body = request.body.read

    if json_body.blank?
      render json: { error: 'Request body is empty' }, status: :bad_request
      return
    end

     # Enqueue the job for background processing
    begin
      MoodleAttendanceJob.perform_later(json_body, app_theme, I18n.locale)
      Rails.logger.info "WebhooksController: MoodleAttendanceJob enqueued. IDs will be derived from JSON body."
      head :accepted # HTTP 202 Accepted: Request accepted for processing
    rescue StandardError => e
      Rails.logger.error "WebhooksController: Failed to enqueue MoodleAttendanceJob. Error: #{e.class} - #{e.message}"
      render json: { error: 'Failed to process webhook' }, status: :internal_server_error
    end
  end

  def brightspace_attendance
    set_current_locale
    json_body = request.body.read

    if json_body.blank?
      render json: { error: 'Request body is empty' }, status: :bad_request
      return
    end

     # Enqueue the job for background processing
    begin
      BrightspaceAttendanceJob.perform_later(json_body, I18n.locale)
      Rails.logger.info "WebhooksController: BrightspaceAttendanceJob enqueued. IDs will be derived from JSON body."
      head :accepted # HTTP 202 Accepted: Request accepted for processing
    rescue StandardError => e
      Rails.logger.error "WebhooksController: Failed to enqueue BrightspaceAttendanceJob. Error: #{e.class} - #{e.message}"
      render json: { error: 'Failed to process webhook' }, status: :internal_server_error
    end
  end
end
