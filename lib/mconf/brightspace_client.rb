module Mconf
  # Client to interact with Brightspace's API
  class BrightspaceClient

    # @param base_url [String] base URL to Brightspace's API
    # @param access_token [String] OAuth2 access token
    # @param api_versions [Hash] API versions to use (default: { lp: '1.54', le: '1.89' })
    # @param user_info [Hash] Optional user information
    def initialize(base_url, access_token, api_versions: nil, user_info: {})
      raise ArgumentError, 'Base URL must be provided' if base_url.blank?
      raise ArgumentError, 'Access token must be provided' if access_token.blank?

      @base_url = base_url
      @access_token = access_token
      # the supported API versions can be found at "#{@base_url}/d2l/api/versions/"
      @api_versions = api_versions || { lp: '1.54', le: '1.89' }
      @user_info_str = "(email: #{user_info[:email]}, launch_nonce: #{user_info[:launch_nonce]})" unless user_info.blank?
    end

    # Fetches the profile image of the authenticated user
    #
    # @return [String, nil] binary data of the profile image, or nil if not found
    def get_profile_image
      url = "#{@base_url}/d2l/api/lp/#{@api_versions[:lp]}/profile/myProfile/image"
      Rails.logger.info "Calling Brightspace API at #{url} to get user profile image #{@user_info_str}"

      res = RestClient.get(url, self.http_headers)
      res.body
    rescue RestClient::NotFound => e
      Rails.logger.warn "Profile image not found in Brightspace: #{e.message}"
      nil
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error "Error calling Brightspace API: #{e.response}"
      nil
    rescue StandardError => e
      Rails.logger.error "Unexpected error calling Brightspace API: #{e.message}"
      nil
    end

    # @return [Hash] HTTP headers including the Authorization header
    def http_headers
      { Authorization: "Bearer #{@access_token}" }
    end
  end
end
