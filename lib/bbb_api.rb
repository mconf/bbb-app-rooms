# frozen_string_literal: true

require 'tests_helper'
require 'nokogiri'
require 'open-uri'

module BbbApi
  include ActionView::Helpers::DateHelper

  def wait_for_mod?(scheduled_meeting, user)
    return unless scheduled_meeting and user
    scheduled_meeting.check_wait_moderator &&
      !user.moderator?(Abilities.moderator_roles) &&
      !scheduled_meeting.check_all_moderators
  end

  def mod_in_room?(scheduled_meeting)
    room = scheduled_meeting.room
    bbb(room).is_meeting_running?(scheduled_meeting.meeting_id)
  end

  def get_participants_count(scheduled_meeting)
    room = scheduled_meeting.room
    meeting_id = scheduled_meeting.meeting_id

    return 0 unless bbb(room).is_meeting_running?(meeting_id)

    res = bbb(room).get_meeting_info(meeting_id, scheduled_meeting.hash_id)
    res[:participantCount]
  end

  def get_current_duration(scheduled_meeting)
    room = scheduled_meeting.room
    meeting_id = scheduled_meeting.meeting_id
    return unless bbb(room).is_meeting_running?(meeting_id)

    res = bbb(room).get_meeting_info(meeting_id, scheduled_meeting.hash_id)
    time_ago_in_words(res[:startTime].to_datetime)
  end

  def join_api_url(scheduled_meeting, user, opts = {})
    return unless scheduled_meeting.present? && user.present?

    room = scheduled_meeting.room
    meeting_id = scheduled_meeting.meeting_id

    unless bbb(room).is_meeting_running?(meeting_id)
      meeting_name = opts[:meeting_name] || scheduled_meeting.meeting_name
      logout_url = opts[:autoclose_url] || autoclose_url

      begin
        bbb(room).create_meeting(
          meeting_name,
          meeting_id,
          scheduled_meeting.create_options(user).merge({ logoutURL: logout_url })
        )
      rescue BigBlueButton::BigBlueButtonException => e
        if ['simultaneousMeetingsLimitReachedForSecret', 'simultaneousMeetingsLimitReachedForInstitution'].include? e.key.to_s
          return { can_join?: false, messageKey: e.key.to_s }
        else
          raise
        end
      end
    end

    is_moderator = user.moderator?(Abilities.moderator_roles) ||
                   scheduled_meeting.check_all_moderators
    role = is_moderator ? 'moderator' : 'viewer'
    locale = I18n.locale == :pt ? 'pt-br' : I18n.locale

    # pre-open the join_api_url with `redirect=false` to check whether the user can join the meeting
    # before actually redirecting him
    if Rails.configuration.check_can_join_meeting
      join_api_url = bbb(room, false).join_meeting_url(
        meeting_id,
        user.username(t("default.bigbluebutton.#{role}")),
        room.attributes[role],
        {
          'userdata-bbb_override_default_locale': locale,
          userID: user.uid,
          redirect: false
        }
      )

      doc = Nokogiri::XML(URI.open(join_api_url))
      hash = Hash.from_xml(doc.to_s)

      Rails.logger.info "BigBlueButtonAPI: (check_can_join_meeting) request=#{join_api_url}"

      if hash['response']['returncode'] == 'FAILED'
        Rails.logger.info "User cannot join meeting, message_key=#{hash['response']['messageKey']}"
        return { can_join?: false, messageKey: hash['response']['messageKey'] }
      end
    end

    join_api_url = bbb(room, false).join_meeting_url(
      meeting_id,
      user.username(t("default.bigbluebutton.#{role}")),
      room.attributes[role],
      {
        'userdata-bbb_override_default_locale': locale,
        userID: user.uid
      }
    )

    { can_join?: true, join_api_url: join_api_url }
  end

  def external_join_api_url(scheduled_meeting, full_name, uid)
    return unless scheduled_meeting.present? && full_name.present?

    room = scheduled_meeting.room
    locale = I18n.locale == :pt ? 'pt-br' : I18n.locale

    join_api_url = bbb(room, false).join_meeting_url(
      scheduled_meeting.meeting_id,
      full_name,
      room.attributes['viewer'],
      { guest: true,
        'userdata-bbb_override_default_locale': locale,
        userID: uid
      }
    )

    { can_join?: true, join_api_url: join_api_url }
  end

  def get_all_meetings(room, options = {})
    res = bbb(room).get_all_meetings(options.merge(room.params_for_get_all_meetings))

    no_more_meetings = res[:nextpage] == 'false'

    # Format playbacks in a more pleasant way.
    res[:meetings].each do |m|
      next if m.key?(:error)
      if m[:recording].present?
        m[:recording][:playbacks] = if !m[:recording][:playback] || !m[:recording][:playback][:format]
                          []
                        elsif m[:recording][:playback][:format].is_a?(Array)
                          m[:recording][:playback][:format]
                        else
                          [m[:recording][:playback][:format]]
                        end

        m[:recording].delete(:playback)
      end
    end

    meetings = res[:meetings].sort_by { |meet| meet[:meeting][:endTime] }.reverse
    [meetings, no_more_meetings]
  end

  # Fetches all recordings for a room.
  def get_recordings(room, options = {})
    res = bbb(room).get_recordings(options.merge(room.params_for_get_recordings))

    # Use this for tests only
    # res = TestsHelper.gen_fake_res(options)

    no_more_recordings = res[:nextpage] == 'false'

    # Format playbacks in a more pleasant way.
    res[:recordings].each do |r|
      next if r.key?(:error)

      r[:playbacks] = if !r[:playback] || !r[:playback][:format]
                        []
                      elsif r[:playback][:format].is_a?(Array)
                        r[:playback][:format]
                      else
                        [r[:playback][:format]]
                      end

      r.delete(:playback)
    end

    recordings = res[:recordings].sort_by { |rec| rec[:endTime] }.reverse
    [recordings, no_more_recordings]
  end

  # Calls getRecodringToken and return the token
  # More about this API call here: https://github.com/mconf/mconf-rec
  def get_recording_token(room, auth_user, meeting_id)
    req_options = { authUser: auth_user, meetingID: meeting_id }
    response = bbb(room).send_api_request(:getRecordingToken, req_options)
    response[:token]
  end

  # Helper for converting BigBlueButton dates into the desired format.
  def recording_date(date)
    date.strftime("%B #{date.day.ordinalize}, %Y.")
  end

  # Helper for converting BigBlueButton dates into a nice length string.
  def recording_length(playbacks)
    # Stats format currently doesn't support length.
    valid_playbacks = playbacks.reject { |p| p[:type] == 'statistics' }
    return '0 min' if valid_playbacks.empty?

    len = valid_playbacks.first[:length]
    if len > 60
      "#{(len / 60).round} hrs"
    elsif len.zero?
      '< 1 min'
    else
      "#{len} min"
    end
  end

  # Deletes a recording from a room.
  def delete_recording(room, record_id)
    bbb(room).delete_recordings(record_id)
  end

  # Publishes a recording for a room.
  def publish_recording(room, record_id)
    bbb(room).publish_recordings(record_id, true)
  end

  # Unpublishes a recording for a room.
  def unpublish_recording(room, record_id)
    bbb(room).publish_recordings(record_id, false)
  end

  # Update recording for a room.
  def update_recording(room, record_id, meta)
    meta[:recordID] = record_id
    bbb(room).send_api_request('updateRecordings', meta)
  end

  private

  # Sets a BigBlueButtonApi object for interacting with the API.
  def bbb(room, internal = true)
    # TODO: consumer_key should never be blank, keeping this condition here just while
    # all rooms migrate to the new format. Remove it after a while.
    consumer_key = if room.consumer_key.blank?
                     room.last_launch.try(:oauth_consumer_key)
                   else
                     room.consumer_key
                   end
    server = ConsumerConfig.find_by(key: consumer_key)&.server

    if server.present?
      Rails.logger.info "Found the server:#{server.domain} secret:#{server.secret[0..7]} "\
                        "for the room:#{room.to_param} " \
                        "using the consumer_key:#{consumer_key}"

      endpoint = if internal && !server.internal_endpoint.blank?
                   server.internal_endpoint
                 else
                   server.endpoint
                 end
      secret = server.secret
    else
      Rails.logger.info "Using the default server for the room:#{room.to_param}, " \
                        "couldn't find one for consumer_key:#{consumer_key}"

      ep = Rails.configuration.bigbluebutton_endpoint
      iep = Rails.configuration.bigbluebutton_endpoint_internal
      endpoint = internal && !iep.blank? ? iep : ep
      secret = Rails.configuration.bigbluebutton_secret
    end

    # BigBlueButtonApi.new(url, secret, version=nil, logger=nil)
    BigBlueButton::BigBlueButtonApi.new(
      remove_slash(fix_bbb_endpoint_format(endpoint)), secret, "0.9", Rails.logger
    )
  end

  # Fixes BigBlueButton endpoint ending.
  def fix_bbb_endpoint_format(url)
    # Fix endpoint format only if required.
    url += '/' unless url.ends_with?('/')
    url += 'api/' if url.ends_with?('bigbluebutton/')
    url += 'bigbluebutton/api/' unless url.ends_with?('bigbluebutton/api/')
    url
  end

  # Removes trailing forward slash from a URL.
  def remove_slash(str)
    str.nil? ? nil : str.chomp('/')
  end
end
