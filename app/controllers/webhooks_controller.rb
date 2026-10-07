# frozen_string_literal: true

class WebhooksController < ApplicationController
  include ApplicationHelper
  include BbbApi
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

    # Only after the task_id has been matched, and against the meeting rooms itself
    # cached: this endpoint has no authentication, so a forged POST must not be able to
    # write metadata onto an arbitrary meeting
    persist_naming_suggestion(room_handler, internal_meeting_id, params['suggested_name'], params['suggested_description'])

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

  private

  # Caches the naming suggestion in the meeting metadata so the listing doesn't ask the
  # Data API on every load
  def persist_naming_suggestion(room_handler, internal_meeting_id, suggested_name, suggested_description)
    room = Room.find_by(handler: room_handler)
    if room.nil?
      Rails.logger.error "[WebhooksController##{__method__}] Room not found for handler='#{room_handler}'"
      return
    end

    meta = if suggested_name.present?
      { 'meta_ai-naming-suggested-title': suggested_name,
        'meta_ai-naming-suggested-description': suggested_description }
    else
      # A suggestion always comes with a successful summary, so its absence here means
      # there will never be one. Clearing the flag is what stops the listing from asking
      # the Data API about this meeting on every load -- and a later request for the
      # artifacts sets it again, as it should
      { 'meta_ai-artifacts-requested': '' }
    end

    update_meeting(room, internal_meeting_id, meta)
    Rails.logger.info "[WebhooksController##{__method__}] Stored the AI naming metadata of internal_meeting_id='#{internal_meeting_id}' (suggestion=#{suggested_name.present?})"
  rescue StandardError => e
    Rails.logger.error "[WebhooksController##{__method__}] Failed to store the AI naming suggestion: #{e.message}"
  end
end
