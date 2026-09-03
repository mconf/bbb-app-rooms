# frozen_string_literal: true

require 'bbb_api'

module ApplicationHelper
  include BbbApi

  def omniauth_bbbltibroker_url(path = nil)
    url = Rails.configuration.omniauth_site[:bbbltibroker]
    url += Rails.configuration.omniauth_root[:bbbltibroker] if Rails.configuration.omniauth_root[:bbbltibroker].present?
    url += path unless path.nil?
    url
  end

  def omniauth_client_token(lti_broker_url)
    oauth_options = {
      grant_type: 'client_credentials',
      client_id: Rails.configuration.omniauth_key[:bbbltibroker],
      client_secret: Rails.configuration.omniauth_secret[:bbbltibroker],
      scope: 'api'
    }
    response = RestClient.post("#{lti_broker_url}/oauth/token", oauth_options)
    JSON.parse(response)['access_token']
  end

  def omniauth_provider?(code)
    provider = code.to_s
    OmniAuth.strategies.each do |strategy|
      return true if provider.downcase == strategy.to_s.demodulize.downcase
    end
    false
  end

  def can_edit?(user, resource)
    Abilities.can?(user, :edit, resource)
  end

  def can_download_recording?(user, resource)
    Abilities.can?(user, :download_presentation_video, resource)
  end

  def can_create_scheduled_meeting?(user, room)
    Abilities.can?(user, :create_scheduled_meeting, room)
  end

  def can_manage_scheduled_meeting?(user, meeting)
    Abilities.can?(user, :manage_scheduled_meeting, meeting)
  end

  def allow_student_scheduling?(room)
    Abilities.allow_student_scheduling?(room)
  end

  def ai_artifacts_enabled?(room)
    @ai_artifacts_enabled_by_consumer_key ||= {}
    consumer_key = room.consumer_key

    return @ai_artifacts_enabled_by_consumer_key[consumer_key] if @ai_artifacts_enabled_by_consumer_key.key?(consumer_key)

    config = ConsumerConfig.find_by(key: consumer_key)
    @ai_artifacts_enabled_by_consumer_key[consumer_key] = config.present? && config.allow_ai_artifacts?
  end

  # Whether the AI documents of a meeting can be offered, from the permission of the
  # user, the configuration of the consumer and the date the feature was released
  #
  # @param date [Date] when the meeting happened, nil when it is not known
  def ai_documents_enabled?(user, room, date)
    return false unless Abilities.full_permission?(user) && ai_artifacts_enabled?(room)

    release_date = Rails.configuration.ai_artifacts_release_date
    return true if release_date.nil?
    # A meeting whose date we don't know stays out, as the check this replaced did
    return false if date.nil?

    date >= release_date
  end

  # The internal meeting id of BBB ends with the timestamp, in milliseconds, of when the
  # meeting was created, which is the only source for its date when it has no recording
  def internal_meeting_date(internal_meeting_id)
    timestamp = internal_meeting_id.to_s.split('-').last
    return nil unless timestamp&.match?(/\A\d{13}\z/)

    Time.at(timestamp.to_i / 1000.0).to_date
  end

  # The playback of a recording that can be downloaded as a file
  def download_format(recording)
    recording[:playbacks].find { |p| p[:type] == 'video' || p[:type] == 'presentation_video' }
  end

  def show_terms_use_message?(resource)
    config = ConsumerConfig.find_by(key: resource[:consumer_key])
    config.present? && config[:message_reference_terms_use]
  end

  def hide_disable_external_link?(resource)
    config = ConsumerConfig.find_by(key: resource[:consumer_key])
    config.present? && config[:force_disable_external_link]
  end

  def hide_recordings_history?(resource)
    config = ConsumerConfig.find_by(key: resource[:consumer_key])
    config.present? && config[:hide_recordings_history] && !(@user.present? && Abilities.full_permission?(@user))
  end

  def show_external_widget?(resource)
    key = ConsumerConfig.find_by(key: resource[:consumer_key])
    key.present? && key[:external_widget]
  end

  def render_external_widget(resource)
    key = ConsumerConfig.find_by(key: resource[:consumer_key])
    key.external_widget.html_safe
  end

  def self.get_shared_secret_guid(resource)
    key = ConsumerConfig.find_by(key: resource[:consumer_key])&.server
    return nil if key.nil?
    key[:shared_secret_guid]
  end

  def theme_defined?
    !Rails.configuration.theme.blank?
  end

  def app_theme
    Rails.configuration.theme
  end

  def device_type?
    agent = request.user_agent
    return "tablet" if agent =~ /(tablet|ipad)|(android(?!.*mobile))/i
    return "mobile" if agent =~ /Mobile/
    return "desktop"
  end

  def theme_class
    "theme-#{Rails.configuration.theme}" if theme_defined?
  end

  def options_for_tooltip(title, options={})
    options.merge!(:title => title,
                   :class => "tooltipped " + (options[:class] || ""),
                   :"data-placement" => options[:"data-placement"] || "top")
  end

  def showable_password_field(form, attribute, options = {})
    value = form.object.try(attribute) unless options[:autofill] == 'off'
    input_id = options[:id] || "#{form.object_name}_#{attribute}"

    input_options = options.merge({
      type: 'password',
      value: value,
      id: input_id,
      class: "#{options[:class]} showable-password"
    })

    field = form.text_field(attribute, input_options)

    ico_show = icon_show_recording(class: 'showable-password-show')
    ico_hide = icon_hide_recording(class: 'showable-password-hide', style: 'display: none;')

    content_tag(:div, field + ico_show + ico_hide, class: 'showable-password-wrapper')
  end

end
