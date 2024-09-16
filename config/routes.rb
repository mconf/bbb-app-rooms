require 'resque/server'

Rails.application.routes.draw do

  get '/health_check', to: 'health_check#all', default: { format: nil }
  get '/healthz', to: 'health_check#all', default: { format: nil }

  if Mconf::Env.fetch_boolean("SERVE_RAILS_ADMIN", false)
    mount RailsAdmin::Engine => '/dash', as: 'rails_admin'

    unless Mconf::Env.fetch_boolean("SERVE_APPLICATION", true)
      root to: redirect('/dash')
    end
  end

  if Rails.configuration.cable_enabled
    mount ActionCable.server => Rails.configuration.action_cable.mount_path
  end

  if Mconf::Env.fetch_boolean("SERVE_APPLICATION", true)
    scope ENV['RELATIVE_URL_ROOT'] || '' do
      scope 'rooms' do
        get '/close', to: 'rooms#close', as: :autoclose

        # Handles recording management.
        scope ':id/recording/:record_id' do
          get '/playback/:playback_type', to: 'rooms#recording_playback', as: :recording_playback
          post '/publish', to: 'rooms#recording_publish', as: :recording_publish
          post '/unpublish', to: 'rooms#recording_unpublish', as: :recording_unpublish
          post '/protect', to: 'rooms#recording_protect', as: :recording_protect
          post '/unprotect', to: 'rooms#recording_unprotect', as: :recording_unprotect
          post '/update', to: 'rooms#recording_update', as: :recording_update
          post '/delete', to: 'rooms#recording_delete', as: :recording_delete
          post '/eduplay', to: 'rooms#eduplay_upload'
          get '/filesender', to: 'rooms#filesender', as: 'filesender'
          post '/filesender', to: 'rooms#filesender_auth'
          post '/filesender_upload', to: 'rooms#filesender_upload'
        end

        # Handles launches.
        match '/launch', to: 'rooms#launch', as: :room_launch, via: [:get, :post]

        # Handles sessions.
        get '/sessions/create'
        get '/sessions/failure'
        get '/sessions/create_session_token', as: :create_session_token

        # Handles Omniauth authentication.
        post '/auth/:provider', to: 'sessions#new', as: :omniauth_authorize
        get '/auth/:provider/callback', to: 'sessions#create', as: :omniauth_callback
        get '/auth/:provider/failure', to: 'sessions#failure', as: :omniauth_failure
        get '/auth/:provider/retry', to: 'sessions#retry', as: :omniauth_retry

        # Handles errors.
        get '/errors/:code', to: 'errors#index', as: :errors

        scope module: :clients do
          scope module: :rnp do
            scope module: :controllers do
              get '/eduplay/callback', to: 'callbacks#eduplay_callback'
              get '/filesender/callback', to: 'callbacks#filesender_callback'
            end
          end
        end

        if Mconf::Env.fetch_boolean("MCONF_SERVE_RESQUE_INTERFACE", false)
          mount Resque::Server.new, at: "/resque"
        end
      end

      # NOTE: there are other actions in the rooms controller, but they are not used for now,
      #       rooms are automatically created when needed and can't be edited
      resources :rooms, only: :show do
        member do
          get :meetings
          get :meetings_pagination
          post :set_current_group_on_session
          get :safari_close
          get '/error/:code', to: 'rooms#error'
        end

        resources :reports, only: :index do
          get :download, on: :collection
        end

        resources :scheduled_meetings, only: [:new, :create, :edit, :update, :destroy] do
          member do
            post :join
            get :join
            get :external
            get :wait
            get :running
            get :updateMeetingData
            get :send_create_calendar_event, to: 'brightspace#send_create_calendar_event'
            get :send_update_calendar_event, to: 'brightspace#send_update_calendar_event'
            get :send_delete_calendar_event, to: 'brightspace#send_delete_calendar_event'
            get :guest_logout, to: 'guest_logout'
          end

          resources :meetings, as: :internal, only: [] do
            get :download_participants, to: 'meetings#download_participants'
            get :download_notes, to: 'meetings#download_notes'
            get :learning_dashboard, to: 'meetings#learning_dashboard'
            get :check_bucket_files, to: 'meetings#check_bucket_files'
          end
        end
      end
    end
  end

  # To treat errors on pages that don't fall on any other controller
  match '*path' => 'application#on_404', via: :all
end
