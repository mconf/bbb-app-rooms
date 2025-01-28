# frozen_string_literal: true

require 'user'
require 'bbb_api'

class MeetingsController < ApplicationController
  include BbbApi

  before_action :find_room
  before_action :get_scheduled_meeting_info
  before_action :check_data_api_config, only: [:download_artifacts]
  before_action :find_app_launch
  before_action :find_user, only: [:download_artifacts]
  before_action only: :download_artifacts do
    authorize_user!(:download_artifacts, @room)
  end

  # GET /rooms/:room_id/scheduled_meetings/:scheduled_meeting_id/meetings/:internal_id/download_artifacts
  def download_artifacts
    render partial: "shared/meeting_data_download"
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
end
