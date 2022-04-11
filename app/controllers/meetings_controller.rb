# frozen_string_literal: true

require 'user'
require 'bbb_api'

class MeetingsController < ApplicationController

  before_action :find_room
  before_action :get_scheduled_meeting_info
  before_action :check_bucket_credentials, only: [:download_notes, :download_participants]
  before_action :check_bucket_access_data, only: [:download_notes, :download_participants]

  # GET /rooms/:room_id/scheduled_meetings/:scheduled_meeting_id/meetings/:internal_id/download_notes
  def download_notes
    filename = MeetingsHelper.filename_for_datafile(:notes)
    url = Mconf::BucketApi.download_url(@meeting, filename)
    redirect_to url
  end

  # GET /rooms/:room_id/scheduled_meetings/:scheduled_meeting_id/meetings/:internal_id/download_participants
  def download_participants
    filename = MeetingsHelper.filename_for_datafile(:participants)
    url = Mconf::BucketApi.download_url(@meeting, filename)
    redirect_to url
  end

  # GET /rooms/:room_id/scheduled_meetings/:scheduled_meeting_id/meetings/:internal_id/check_bucket_files
  def check_bucket_files
    @notes_exist = MeetingsHelper.file_exists_on_bucket?(@meeting, @room, :notes)
    @participants_exist = MeetingsHelper.file_exists_on_bucket?(@meeting, @room, :participants)

    render partial: "shared/meeting_data_download"
  end

  protected

  def get_scheduled_meeting_info
    @meeting = {}
    @meeting[:meetingID] = params[:scheduled_meeting_id]
    @meeting[:internalMeetingID] = params[:internal_id]
    @meeting[:room] = @room
  end

  # Checks if the bucket credentials are present on config/application.rb
  def check_bucket_credentials
    unless MeetingsHelper.bucket_configured?
      Rails.logger.error "A bucket credential is missing from the .env file"
      flash[:error] = t("bucket_api.credentials_missing")
      redirect_to previous_path_or(meetings_room_path)
    end
  end

  # Checks if the needed data to build the download url is present
  def check_bucket_access_data
    unless MeetingsHelper.has_required_info_for_bucket?(@meeting)
      Rails.logger.error "Bucket access data is missing"
      flash[:error] = t("bucket_api.access_data_missing")
      redirect_to previous_path_or(meetings_room_path)
    end
  end
end
