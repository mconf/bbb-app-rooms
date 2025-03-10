class ReportsController < ApplicationController
  include ApplicationHelper

  before_action :find_room
  before_action :check_data_api_config
  before_action :find_user
  before_action :find_app_launch
  before_action do
    authorize_user!(:edit, @room)
  end

  # GET /rooms/:id/reports
  def index
    respond_to do |format|
      @reports = Mconf::DataApi.reports_available(@room.consumer_config.key, @room.handler)&.reverse()
      format.html { render 'rooms/reports' }
    end
  end

  # GET /rooms/:id/report/download
  def download
    @report_artifacts = Mconf::DataApi.get_report_artifacts(@room.consumer_config.key, @room.handler, params[:period], I18n.locale)

    render partial: "shared/report_data_download"
  end

  private

  def check_data_api_config
    if Rails.application.config.data_api_url.blank?
      Rails.logger.error "Data API url is missing from the .env file"
      redirect_back(fallback_location: room_path(@room),
                      notice: t('default.app.data_api_config_error'))
    end
  end
end
