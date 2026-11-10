# frozen_string_literal: true

require 'user'
require './lib/mconf/elos_analytics'

# Hands a room over to the engagement dashboard, which runs as a separate application.
#
# #launch builds a signed token and renders the form that posts it; #jwks publishes the
# public key the dashboard verifies that token with. The dashboard keeps no login of its
# own, so this pair is the whole of how someone gets in.
class ElosAnalyticsController < ApplicationController
  include ApplicationHelper

  before_action :find_room, except: :jwks
  before_action :find_user, except: :jwks
  before_action :find_app_launch, except: :jwks
  before_action :set_institution_guid, except: :jwks
  before_action except: :jwks do
    authorize_user!(:edit, @room)
  end
  before_action :ensure_elos_analytics_allowed, except: :jwks

  # GET /rooms/:id/elos_analytics
  def launch
    @launch_url = Rails.configuration.elos_analytics_launch_url
    @token = Mconf::ElosAnalytics.launch_token(room: @room, user: @user, app_launch: @app_launch)

    # No layout: the page exists only to post the form and go away.
    render :launch, layout: false
  rescue Mconf::ElosAnalytics::ConfigurationError => e
    Rails.logger.error("[elos_analytics] could not issue a launch token: #{e.message}")
    redirect_to room_path(@room), notice: t('default.app.elos_analytics_config_error')
  end

  # GET /rooms/elos_analytics/jwks
  #
  # Public by design: a public key is what everyone is meant to have. Cached because it
  # changes only when a key is rotated.
  def jwks
    expires_in 1.hour, public: true
    render json: LaunchSigningKey.key_set
  end

  private

  def ensure_elos_analytics_allowed
    return if elos_analytics_enabled?(@room)

    Rails.logger.info(
      "[elos_analytics] refused: room #{@room.handler} belongs to a consumer with the dashboard disabled"
    )
    redirect_to room_path(@room), notice: t('default.app.elos_analytics_config_error')
  end
end
