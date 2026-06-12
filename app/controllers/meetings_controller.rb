# frozen_string_literal: true

require 'user'
require 'bbb_api'

class MeetingsController < ApplicationController
  include BbbApi

  before_action :find_room
  before_action :get_scheduled_meeting_info
  before_action :check_data_api_config, only: [:download_artifacts, :download_ai_artifacts]
  before_action :find_app_launch
  before_action :find_user, only: [:download_artifacts, :download_ai_artifacts, :request_ai_artifacts]
  before_action :set_institution_guid
  before_action only: :download_artifacts do
    authorize_user!(:download_artifacts, @room)
  end
  before_action only: :download_ai_artifacts do
    authorize_user!(:download_artifacts, @room)
  end
  before_action only: :request_ai_artifacts do
    authorize_user!(:download_artifacts, @room)
  end

  # GET /rooms/:room_id/scheduled_meetings/:scheduled_meeting_id/meetings/:internal_id/download_artifacts
  def download_artifacts
    @artifact_files = Mconf::DataApi.get_meeting_artifacts_files(
      @institution_guid,
      @meeting[:internalMeetingID],
      I18n.locale.to_s
    )

    render partial: "shared/meeting_data_download"
  end

  # GET /rooms/:room_id/scheduled_meetings/:scheduled_meeting_id/meetings/:internal_id/download_ai_artifacts
  def download_ai_artifacts
    @ai_artifact_files = Mconf::DataApi.get_meeting_artifacts_files(
      @institution_guid,
      @meeting[:internalMeetingID],
      I18n.locale.to_s
    )
    @ai_artifact_cache_status = read_artifact_cache_status

    render partial: "shared/meeting_ai_artifacts"
  end

  ALLOWED_ARTIFACT_TYPES = %w[ai_summary transcription].freeze

  # POST /rooms/:room_id/scheduled_meetings/:scheduled_meeting_id/meetings/:internal_id/request_ai_artifacts
  def request_ai_artifacts
    requested_types = Array(params[:requested_artifact_types])
      .select { |t| ALLOWED_ARTIFACT_TYPES.include?(t) }
      .presence || ALLOWED_ARTIFACT_TYPES

    response = Mconf::LlmApi.request_ai_artifacts(@meeting[:internalMeetingID])

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
