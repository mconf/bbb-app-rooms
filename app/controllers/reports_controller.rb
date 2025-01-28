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
      start_date = @room.consumer_config.created_at
      current_date = Date.today
      periods = []

      while current_date >= start_date
        periods << current_date.strftime("%Y-%m")
        current_date = current_date.prev_month
      end

      @reports = periods
      format.html { render 'rooms/reports' }
    end
  end

  # GET /rooms/:id/report/download
  def download
    report_artifacts = Mconf::DataApi.get_report_artifacts(@app_launch.params['custom_params']['institution_guid'], params[:period], I18n.locale)
    redirect_to report_artifacts["#{params[:file_format]}"]
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
