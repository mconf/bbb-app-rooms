# frozen_string_literal: true

require 'brightspace_helper'

class BrightspaceController < ApplicationController
  include ApplicationHelper
  include BrightspaceHelper

  # make sure the user has access to the room and meeting
  before_action :find_room
  before_action :validate_room
  before_action :find_user
  before_action :find_scheduled_meeting, except: [:send_delete_calendar_event, :fetch_profile_image]
  before_action :validate_scheduled_meeting, except: [:send_delete_calendar_event, :fetch_profile_image]
  before_action -> { authorize_user!(:edit, @room) }, except: [:fetch_profile_image]
  before_action :prevent_event_duplication, only: :send_create_calendar_event
  before_action :find_app_launch
  before_action :set_event
  before_action -> { authenticate_with_oauth! :brightspace, @custom_params }

  # GET /rooms/:room_id/brightspace/fetch_profile_image
  def fetch_profile_image
    base_url = @app_launch.brightspace_oauth.url
    access_token = @app_launch.omniauth_auth.dig('brightspace','credentials', 'token')
    user_info = { email: @user.email, launch_nonce: @app_launch.nonce }
    brightspace_client = Mconf::BrightspaceClient.new(base_url, access_token, user_info: user_info)

    profile_image = brightspace_client.get_profile_image
    file_name = "#{@app_launch.consumer_key}/#{@user.uid}.jpg" # unique file name per LMS and user
    # Upload the profile image to S3 and set the profile_image_url param on AppLaunch
    if profile_image.present? && Mconf::S3Client.upload_public_file(profile_image, file_name)
      @app_launch.set_param('profile_image_url', Mconf::S3Client.public_url_for(file_name))
    end

    redirect_to room_path(@room)
  end

  def send_create_calendar_event
    begin
      event_data = send_calendar_event(:create,
                                       @app_launch,
                                       scheduled_meeting: @scheduled_meeting)


      local_params = { event_id: event_data[:event_id],
                       link_id: event_data[:lti_link_id],
                       scheduled_meeting_hash_id: @scheduled_meeting.hash_id,
                       room_id: @scheduled_meeting.room_id, }
      BrightspaceCalendarEvent.find_or_create_by(local_params)
    rescue BrightspaceHelper::SendCalendarEventError => e
      Rails.logger.warn("Failed to receive send_create_calendar_event data, " \
                        "not creating BrightspaceCalendarEvent on DB. " \
                        "Error: #{e.message}")
    end

    redirect_to(*pop_redirect_from_session!('brightspace_return_to'))
  end

  def send_update_calendar_event
    begin
      event_data = send_calendar_event(:update,
                                       @app_launch,
                                       scheduled_meeting: @scheduled_meeting)

      local_params = { event_id: event_data[:event_id],
                       link_id: event_data[:lti_link_id],
                       room_id: @scheduled_meeting.room_id, }
      BrightspaceCalendarEvent
        .find_or_create_by(scheduled_meeting_hash_id: @scheduled_meeting.hash_id)
        &.update(local_params)
    rescue BrightspaceHelper::SendCalendarEventError => e
      Rails.logger.warn("Failed to receive send_update_calendar_event data, " \
                        "not updating BrightspaceCalendarEvent on DB." \
                        "Error: #{e.message}")
    end

    redirect_to(*pop_redirect_from_session!('brightspace_return_to'))
  end

  def send_delete_calendar_event
    begin
      send_calendar_event(:delete,
                          @app_launch,
                          scheduled_meeting_hash_id: permitted_params[:id],
                          room: @room)
      BrightspaceCalendarEvent
        .find_by(scheduled_meeting_hash_id: permitted_params[:id], room_id: @room.id)
        &.delete
    rescue BrightspaceHelper::SendCalendarEventError => e
      Rails.logger.warn("Failed to send delete calendar event. " \
                        "Error: #{e.message}")
    end

    redirect_to(*pop_redirect_from_session!('brightspace_return_to'))
  end

  private

  def prevent_event_duplication
    event = @scheduled_meeting.brightspace_calendar_event
    return unless event

    Rails.logger.info('Brightspace calendar event already sent.')
    redirect_to(@room)
  end

  def set_event
    # clear param :session_set to avoid conflict with the previous "bbltibroker" auth
    params.delete(:session_set)
    @custom_params = permitted_params.to_h
    @custom_params[:launch_nonce] = @app_launch.nonce
    @custom_params[:event] = action_name
  end

  def permitted_params
    params.permit(:room_id, :id, :app_id, :event_id)
  end
end
