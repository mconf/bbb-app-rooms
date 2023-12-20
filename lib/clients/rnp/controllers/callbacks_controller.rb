module Clients::Rnp
  module Controllers
    class CallbacksController < ApplicationController

      def eduplay_callback
        response = Eduplay::API.get_access_token(params[:code])
        @access_token = response['access_token']
        @expires_at = Time.now + response['expires_in'].to_i
        @recordID = params[:state]

        render 'callbacks/eduplay_callback'
      end

      def filesender_callback
        response = Filesender::API.get_access_token(params[:code])
        @access_token = response['access_token']
        @expires_at = Time.now + response['expires_in'].to_i
        @recordID = params[:state]

        render 'callbacks/filesender_callback'
      end
    end
  end
end
