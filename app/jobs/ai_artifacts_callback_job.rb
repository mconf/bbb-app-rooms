# frozen_string_literal: true

class AiArtifactsCallbackJob < ApplicationJob
  queue_as :default

  STATUS_BY_TYPE = {
    'ai_summary'    => 'summary_status',
    'transcription' => 'transcription_status'
  }.freeze

  def perform(json_body)
    params = JSON.parse(json_body)

    task_id = params['task_id']
    cached_context = Rails.cache.read("llm_callback_#{task_id}")
    if cached_context.nil?
      Resque.logger.error "[AIArtifactsCallbackJob] No cached context for task_id='#{task_id}'"
      return
    end

    room_handler = cached_context[:room_handler]
    internal_meeting_id = cached_context[:internal_meeting_id]
    requested_types = cached_context[:requested_artifact_types]

    cache_ttl = Rails.application.config.llm_artifact_cache_ttl.seconds

    requested_types.each do |type|
      cache_key = "meeting_ai_artifact_#{room_handler}_#{internal_meeting_id}_#{type}"
      if params[STATUS_BY_TYPE[type]] == 'success'
        Rails.cache.delete(cache_key)
      else
        Rails.cache.write(cache_key, { status: 'error' }, expires_in: cache_ttl)
      end
    end

    Rails.cache.delete("llm_callback_#{task_id}")
  rescue JSON::ParserError => e
    Resque.logger.error "[AiArtifactsCallbackJob] Failed to parse JSON: #{e.message}"
  end
end
