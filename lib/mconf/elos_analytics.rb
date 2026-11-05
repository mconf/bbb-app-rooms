# frozen_string_literal: true

module Mconf
  # Builds the token that hands a room over to the engagement dashboard.
  #
  # The dashboard is a separate application with no login of its own, so this token is
  # the only way into it. It travels in the body of a form the browser posts, never in a
  # URL, and the dashboard refuses it after the first use.
  class DashMr
    class ConfigurationError < StandardError; end

    SCOPE_TYPE = 'lti_context'

    # LTI sends roles either plain ("Instructor") or as a URN
    # ("urn:lti:role:ims/lis/Instructor"). The dashboard compares them as plain
    # lowercase names, so only the last segment is sent.
    ROLE_SEPARATORS = %r{[:/]}

    def self.launch_token(room:, user:, app_launch: nil)
      new(room: room, user: user, app_launch: app_launch).launch_token
    end

    def initialize(room:, user:, app_launch: nil)
      @room = room
      @user = user
      @app_launch = app_launch
    end

    def launch_token
      check_configuration

      key = LaunchSigningKey.current
      JWT.encode(payload, key.private_rsa, LaunchSigningKey::ALGORITHM, kid: key.kid)
    end

    private

    def payload
      now = Time.now.to_i

      {
        iss: config.dash_mr_issuer,
        aud: config.dash_mr_audience,
        sub: subject,
        iat: now,
        # Short lived on purpose: the token only has to survive the post to the
        # dashboard, which claims it once and refuses every later use.
        exp: now + config.dash_mr_token_ttl,
        jti: SecureRandom.uuid,
        name: @user.username(@user.uid),
        email: @user.email,
        roles: roles,
        scope: {
          type: SCOPE_TYPE,
          consumer_key: consumer_key,
          handler: @room.handler,
          institution_guid: institution_guid,
        },
      }
    end

    # Identifies the person within the course they arrived in, which is as far as the
    # dashboard needs to tell people apart.
    def subject
      "lti:#{context_id}:#{@user.uid}"
    end

    def context_id
      @app_launch&.params&.[]('context_id').presence || @room.handler
    end

    # The analytics routes the dashboard reads are keyed by consumer key and room
    # handler, so without the key it cannot build a single URL.
    #
    # Falls back to the last launch for the same reason `bbb_api.rb` does: the column
    # should always be filled, but rooms created before it existed still have it blank.
    # The institution guid is then read from the consumer config this resolves to, and
    # not from Room#institution_guid, which looks the config up by the column alone —
    # for a legacy room that lookup finds nothing, so the two have to travel together.
    def consumer_key
      @consumer_key ||= @room.consumer_key.presence || @room.last_launch.try(:oauth_consumer_key)
    end

    def consumer_config
      return @consumer_config if defined?(@consumer_config)

      @consumer_config = ConsumerConfig.find_by(key: consumer_key)
    end

    def institution_guid
      consumer_config&.institution_guid
    end

    def roles
      @user.roles.to_s.split(',').map { |role| role.strip.split(ROLE_SEPARATORS).last.to_s.downcase }.reject(&:blank?)
    end

    # Without these the dashboard has no course to show and nothing to scope its calls
    # to the Data API with, so the launch is stopped here rather than halfway through,
    # somewhere less obvious.
    #
    # The consumer check is repeated from the controller on purpose: this is where a
    # token is actually minted, and minting one for an institution that was never
    # enabled is the thing that must not happen, whoever the caller is.
    def check_configuration
      raise ConfigurationError, 'MCONF_DASH_MR_LAUNCH_URL is missing' if config.dash_mr_launch_url.blank?
      raise ConfigurationError, "room #{@room.handler} has no consumer key" if consumer_key.blank?
      raise ConfigurationError, "room #{@room.handler} has no institution guid" if institution_guid.blank?
      return if consumer_config&.allow_dash_mr?

      raise ConfigurationError, "consumer #{consumer_key} does not have the dashboard enabled"
    end

    def config
      Rails.configuration
    end
  end
end
