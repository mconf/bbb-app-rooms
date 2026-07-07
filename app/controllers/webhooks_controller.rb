# frozen_string_literal: true

class WebhooksController < ApplicationController
  include ApplicationHelper
  AI_ARTIFACT_STATUS_KEY = {
    'ai_summary'    => 'summary_status',
    'transcription' => 'transcription_status'
  }.freeze

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

  def ai_artifacts
    json_body = request.body.read

    if json_body.blank?
      render json: { error: 'Request body is empty' }, status: :bad_request
      return
    end

    params = JSON.parse(json_body)
    task_id = params['task_id'].to_s
    cached_context = Rails.cache.read("llm_callback_#{task_id}")

    if cached_context.nil?
      Rails.logger.error "[WebhooksController#ai_artifacts] No cached context for task_id='#{task_id}'"
      render json: { error: 'Unknown task_id' }, status: :not_found
      return
    end

    room_handler = cached_context[:room_handler]
    internal_meeting_id = cached_context[:internal_meeting_id]
    requested_types = cached_context[:requested_artifact_types]
    cache_ttl = Rails.application.config.llm_artifact_cache_ttl.seconds

    requested_types.each do |type|
      cache_key = "meeting_ai_artifact_#{room_handler}_#{internal_meeting_id}_#{type}"
      if params[AI_ARTIFACT_STATUS_KEY[type]] == 'success'
        Rails.cache.delete(cache_key)
      else
        Rails.cache.write(cache_key, { status: 'error' }, expires_in: cache_ttl)
      end
    end

    Rails.cache.delete("llm_callback_#{task_id}")
    head :ok
  rescue JSON::ParserError => e
    Rails.logger.error "[WebhooksController#ai_artifacts] Failed to parse JSON: #{e.message}"
    render json: { error: 'Invalid JSON' }, status: :bad_request
  end
end
