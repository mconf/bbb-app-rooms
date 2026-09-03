# frozen_string_literal: true

require 'user'
require 'bbb_api'

class MeetingsController < ApplicationController
  include BbbApi

  before_action :find_room
  before_action :get_scheduled_meeting_info
  before_action :check_data_api_config, only: :download_documents
  before_action :find_app_launch
  before_action :find_user, only: [:download_documents, :request_ai_artifacts]
  before_action :set_institution_guid
  before_action only: :download_documents do
    # The dropdown also lists the recording, which a user who cannot download the
    # documents may still be allowed to download. What each one sees is decided by the
    # partial, this only keeps out whoever can see neither
    authorize_user!(:download_artifacts, @room) unless Abilities.can?(@user, :download_presentation_video, @room)
  end
  before_action only: :request_ai_artifacts do
    authorize_user!(:download_artifacts, @room)
  end

  # GET /rooms/:room_id/scheduled_meetings/:scheduled_meeting_id/meetings/:internal_id/download_documents
  def download_documents
    documents = Mconf::DataApi.get_meeting_documents(
      @institution_guid,
      @meeting[:internalMeetingID],
      I18n.locale.to_s
    ) || {}

    @meeting_documents = documents['meeting'] || {}
    @session_documents = documents['session'] || {}
    @recording_documents = documents['recording'] || {}
    @has_session_objects = documents['has_session_objects']

    # The recording is fetched on every render, like the documents are, so one that was
    # still being processed when the page loaded turns into a download once it is ready.
    # In BBB the record id of a meeting is its internal meeting id, and 'state' has to be
    # asked for explicitly: the API only answers with the published ones by default,
    # which would leave a recording still being processed out
    @recording = get_recordings(@room, recordID: @meeting[:internalMeetingID], state: 'any').first.first
    @ai_artifact_cache_status = read_artifact_cache_status

    render partial: "shared/meeting_documents"
  end

  ALLOWED_ARTIFACT_TYPES = %w[ai_summary transcription].freeze

  # POST /rooms/:room_id/scheduled_meetings/:scheduled_meeting_id/meetings/:internal_id/request_ai_artifacts
  def request_ai_artifacts
    requested_types = Array(params[:requested_artifact_types])
      .select { |t| ALLOWED_ARTIFACT_TYPES.include?(t) }
      .presence || ALLOWED_ARTIFACT_TYPES

    response = Mconf::LlmApi.request_ai_artifacts(@meeting[:internalMeetingID])

    if response.nil?
      render json: { status: 'error', message: t('meetings.request_artifact.error_requesting_artifacts') }, status: :bad_request
      return
    end

    if response.body["error"].present?
      error_message = case response.status
      when 404
        t('meetings.request_artifact.error_404')
      when 409
        t('meetings.request_artifact.error_409')
      when 412
        t('meetings.request_artifact.error_412')
      else
        t('meetings.request_artifact.error_requesting_artifacts')
      end

      Rails.logger.error "[MeetingsController##{__method__}] LLM API error (#{response.status})" \
        " for internal_meeting_id='#{@meeting[:internalMeetingID]}': #{response.body}"

      render json: { status: 'error', message: error_message }, status: :unprocessable_entity
      return
    end

    cache_ttl = Rails.application.config.llm_artifact_cache_ttl.seconds

    task_id = response.body['task_id']
    if task_id.present?
      Rails.cache.write("llm_callback_#{task_id}", {
        room_handler: @room.handler,
        internal_meeting_id: @meeting[:internalMeetingID],
        requested_artifact_types: requested_types
      }, expires_in: cache_ttl)
    end

    requested_types.each do |artifact_type|
      Rails.cache.write(artifact_cache_key(artifact_type), { status: 'pending' }, expires_in: cache_ttl)
    end

    render json: { status: 'ok', message: t('meetings.request_artifact.request_successful') }
  rescue Mconf::LlmApi::ApiUrlMissingError => e
    Rails.logger.error "[MeetingsController##{__method__}] #{e.message}"
    render json: { status: 'error', message: t('meetings.request_artifact.error_requesting_artifacts') }, status: :internal_server_error
  rescue => e
    Rails.logger.error "[MeetingsController##{__method__}] Unexpected error for" \
      " internal_meeting_id='#{@meeting[:internalMeetingID]}': #{e.message}"
    render json: { status: 'error', message: t('meetings.request_artifact.error_requesting_artifacts') }, status: :internal_server_error
  end

  protected

  def get_scheduled_meeting_info
    @meeting = {}
    @meeting[:meetingID] = params[:scheduled_meeting_id]
    @meeting[:internalMeetingID] = params[:internal_id]
    @meeting[:room] = @room
    # endTime never changes after the meeting ends, so unlike the recording it is passed
    # along by the page instead of being fetched again
    @meeting[:endTime] = params[:end_time]
    @meeting[:running] = params[:running]
  end

  def check_data_api_config
    if Rails.application.config.data_api_url.blank?
      Rails.logger.error "Data API url is missing from the .env file"
      redirect_back(fallback_location: room_path(@room),
                      notice: t('default.app.data_api_config_error'))
    end
  end

  def artifact_cache_key(artifact_type)
    "meeting_ai_artifact_#{@room.handler}_#{@meeting[:internalMeetingID]}_#{artifact_type}"
  end

  def read_artifact_cache_status
    ALLOWED_ARTIFACT_TYPES.each_with_object({}) do |type, result|
      cached = Rails.cache.read(artifact_cache_key(type))
      result[type] = cached&.dig(:status)
    end
  end
end
