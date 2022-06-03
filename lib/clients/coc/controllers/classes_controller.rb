module Clients::Coc
  module Controllers
    class ClassesController < ApplicationController
      include ApplicationHelper

      before_action -> { authenticate_with_oauth!(:bbbltibroker) },
                    only: :launch, raise: false
      before_action :set_launch_room, only: %i[launch]
      before_action :find_app_launch, only: %i[index show]
      before_action :find_user
      before_action only: %i[launch index show] do
        authorize_user!(:show, nil)
      end

      # GET /launch
      def launch
        schools = @app_launch.params.dig('custom_params', 'schools')
        classes_count = Helpers::CocHelper.classes_count(schools)

        # Don't need to redirect to classes_path if user has access to only 1 class
        if classes_count > 1
          redirect_to(coc_classes_path(@app_launch.room_handler))
        else
          klass = Helpers::CocHelper.get_single_class(schools)
          redirect_to(coc_classes_show_path(handler: @app_launch.room_handler, class_id: klass['id']))
        end
      end

      # GET /coc/classes/:handler
      def index
        respond_to do |format|
          format.html do
            schools = @app_launch.params.dig('custom_params', 'schools')
            @schools = Helpers::CocHelper.sort_schools(schools)
            render "classes/index"
          end
        end
      end

      # GET /coc/:handler/:class_id
      def show
        adapted_room_params = adapt_room_params

        @room = Room.create_with(adapted_room_params)
                    .find_or_create_by(handler: adapted_room_params[:handler])
        @room.update(adapted_room_params) if @room.present?
        # Create the user session
        # Keep it as small as possible, most of the data is in the AppLaunch
        set_room_session(
          @room, { launch: @app_launch.nonce, is_coc: true }
        )

        redirect_to(room_path(@room))
      end

      private

      def adapt_room_params
        coc_class_with_grade = Helpers::CocHelper.get_class_full_data(@app_launch.params.dig('custom_params', 'schools'),
                                                                      params[:class_id])

        adapted_room_params = @app_launch.room_params
        adapted_room_params[:handler] = Digest::SHA1.hexdigest(
          'coc' + params[:handler] + params['class_id']
        ).to_s
        adapted_room_params[:name] = "#{coc_class_with_grade['grade']['name']} | " \
                                     "#{coc_class_with_grade['name']}" || ''
        adapted_room_params[:description] = "#{coc_class_with_grade['school']['name']} | " \
                                            "#{coc_class_with_grade['segment']['name']}" || ''
        adapted_room_params
      end

      def set_launch_room
        launch_nonce = params['launch_nonce']

        # Pull the Launch request_parameters
        bbbltibroker_url = omniauth_bbbltibroker_url("/api/v1/sessions/#{launch_nonce}")
        Rails.logger.info("Making a session request to #{bbbltibroker_url}")
        session_params = JSON.parse(
          RestClient.get(
            bbbltibroker_url,
            'Authorization' => "Bearer #{omniauth_client_token(omniauth_bbbltibroker_url)}"
          )
        )

        unless session_params['valid']
          Rails.logger.info('The session is not valid, returning a 403')
          set_error('room', 'forbidden', :forbidden)
          respond_with_error(@error)
          return
        end

        launch_params = session_params['message']
        if launch_params['user_id'] != session['omniauth_auth']['bbbltibroker']['uid']
          Rails.logger.info("The user in the session doesn't match the user in the launch, returning a 403")
          set_error('room', 'forbidden', :forbidden)
          respond_with_error(@error)
          return
        end
        launch_params['custom_params']['tag'] = 'coc'

        bbbltibroker_url = omniauth_bbbltibroker_url("/api/v1/sessions/#{launch_nonce}/invalidate")
        Rails.logger.info("Making a session request to #{bbbltibroker_url}")
        session_params = JSON.parse(
          RestClient.get(
            bbbltibroker_url,
            'Authorization' => "Bearer #{omniauth_client_token(omniauth_bbbltibroker_url)}"
          )
        )

        AppLaunch.remove_old_app_launches if Rails.application.config.launch_remove_old_on_launch

        # Store the data from this launch for easier access
        expires_at = Rails.configuration.launch_duration_mins.from_now
        @app_launch = AppLaunch.find_or_create_by(nonce: launch_nonce) do |launch|
          launch.update(
            params: launch_params,
            omniauth_auth: session['omniauth_auth']['bbbltibroker'],
            expires_at: expires_at
          )
        end

        # Use this data only during the launch
        # From now on, take it from the AppLaunch
        session.delete('omniauth_auth')
        set_coc_session(@app_launch.room_params[:handler], {nonce: launch_nonce})
      end

      def get_coc_session(handler)
        session[COOKIE_ROOMS_SCOPE] ||= {}
        return if handler.blank?

        session[COOKIE_ROOMS_SCOPE][handler]
      end

      def set_coc_session(handler, data)
        session[COOKIE_ROOMS_SCOPE] ||= {}

        # so we know which ones are the oldest ones
        data['ts'] = DateTime.now.to_i
    
        cleanup_room_session unless session[COOKIE_ROOMS_SCOPE].key?(handler)

        # they will be strings in future calls, so make them strings already
        session[COOKIE_ROOMS_SCOPE][handler] = data.stringify_keys
      end

      def find_app_launch
        coc_session = get_coc_session(params[:handler])
        @app_launch = AppLaunch.find_by(nonce: coc_session['nonce']) if coc_session.present?
        redirect_to errors_path(404) unless @app_launch.present?
      end

      def permitted_params
        params.permit('launch_nonce', 'handler')
      end
    end
  end
end
