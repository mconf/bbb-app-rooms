module Mconf
  # Client to interact with Brightspace's API
  class BrightspaceClient

    # @param base_url [String] base URL to Brightspace's API
    # @param access_token [String] OAuth2 access token
    # @param api_versions [Hash] API versions to use (default: { lp: '1.54', le: '1.89' })
    # @param user_info [Hash] Optional user information
    def initialize(base_url, access_token, api_versions: nil, user_info: {}, logger: Rails.logger)
      raise ArgumentError, 'Base URL must be provided' if base_url.blank?
      raise ArgumentError, 'Access token must be provided' if access_token.blank?

      @base_url = base_url
      @access_token = access_token
      # the supported API versions can be found at "#{@base_url}/d2l/api/versions/"
      @api_versions = api_versions || { lp: '1.54', le: '1.89' }
      @user_info_str = ""
      @user_info_str = "[email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}]" if user_info.present?
      @logger = logger
      @logger.info "[BrightspaceClient] Initialized with base_url=#{@base_url} #{@user_info_str}"
    end

    # Fetches the profile image of the authenticated user
    # @param size [Integer] size of the profile image in pixels (default: 200)
    # @return [String, nil] binary data of the profile image, or nil if not found
    def get_profile_image(size: 200)
      url = "#{@base_url}/d2l/api/lp/#{@api_versions[:lp]}/profile/myProfile/image?size=#{size}"
      @logger.info "[BrightspaceClient] Calling #{url} to get user profile image #{@user_info_str}"

      res = RestClient.get(url, self.http_headers)
      res.body
    rescue RestClient::NotFound => e
      @logger.info "[BrightspaceClient]#{@user_info_str} Profile image not found, response: #{e.message}"
      nil
    rescue RestClient::ExceptionWithResponse => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} RestClient error: #{e.response}"
      nil
    rescue StandardError => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} Unexpected error: #{e.message}"
      nil
    end

    # Retrieve all the current grade objects for a provided course
    # https://docs.valence.desire2learn.com/res/grade.html#get--d2l-api-le-(version)-(orgUnitId)-grades-
    # @param course_id [Integer] ID of the course
    # @return [Hash, nil] JSON response with grade objects, or nil on error
    def get_course_grade_objects(course_id)
      url = "#{@base_url}/d2l/api/le/#{@api_versions[:le]}/#{course_id}/grades/"
      @logger.info "[BrightspaceClient] Calling #{url} to get grade objects from course #{course_id} #{@user_info_str}"

      res = RestClient.get(url, self.http_headers)
      JSON.parse(res.body)
    rescue RestClient::ExceptionWithResponse => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} RestClient error: #{e.response}"
      nil
    rescue StandardError => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} Unexpected error: #{e.message}"
      nil
    end

    # Retrieve a list of all grade categories for a provided course
    # https://docs.valence.desire2learn.com/res/grade.html#get--d2l-api-le-(version)-(orgUnitId)-grades-categories-
    # @param course_id [Integer] ID of the course
    # @return [Hash, nil] JSON response with grade categories, or nil on error
    def get_course_grade_categories(course_id)
      url = "#{@base_url}/d2l/api/le/#{@api_versions[:le]}/#{course_id}/grades/categories/"
      @logger.info "[BrightspaceClient] Calling #{url} to get grade categories from course #{course_id} #{@user_info_str}"

      res = RestClient.get(url, self.http_headers)
      JSON.parse(res.body)
    rescue RestClient::ExceptionWithResponse => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} RestClient error: #{e.response}"
      nil
    rescue StandardError => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} Unexpected error: #{e.message}"
      nil
    end

    # Creates a grade category in a provided course
    # https://docs.valence.desire2learn.com/res/grade.html#post--d2l-api-le-(version)-(orgUnitId)-grades-categories-
    # @param course_id [Integer] ID of the course
    # @param name [String] Name of the grade category (default: "Presença nas aulas online")
    # @param short_name [String] Short name of the grade category (default: "Presença nas aulas online")
    # @return [Hash, nil] JSON response with created grade category, or nil on error
    def create_course_grade_category(course_id, name: nil, short_name: nil)
      url = "#{@base_url}/d2l/api/le/#{@api_versions[:le]}/#{course_id}/grades/categories/"
      @logger.info "[BrightspaceClient] Calling #{url} to create a grade category in course #{course_id} #{@user_info_str}"

      payload = {
        "Name": name || "Presença nas aulas online",
        "ShortName": short_name || "Presença nas aulas online",
        "CanExceedMax": false,
        "ExcludeFromFinalGrade": false,
        "StartDate": nil,
        "EndDate": nil,
        "Weight": nil,
        "MaxPoints": 10,
        "AutoPoints": nil,
        "WeightDistributionType": nil,
        "NumberOfHighestToDrop": nil,
        "NumberOfLowestToDrop": nil
      }

      res = RestClient.post(url, payload.to_json, self.http_headers.merge(content_type: :json, accept: :json))
      JSON.parse(res.body)
    rescue RestClient::ExceptionWithResponse => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} RestClient error: #{e.response}"
      nil
    rescue StandardError => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} Unexpected error: #{e.message}"
      nil
    end

    # Retrieve all the grade schemes for a provided course
    # https://docs.valence.desire2learn.com/res/grade.html#get--d2l-api-le-(version)-(orgUnitId)-grades-schemes-
    # @param course_id [Integer] ID of the course
    # @return [Hash, nil] JSON response with grade schemes, or nil on error
    def get_course_grade_schemes(course_id)
      url = "#{@base_url}/d2l/api/le/#{@api_versions[:le]}/#{course_id}/grades/schemes/"
      @logger.info "[BrightspaceClient] Calling #{url} to get grade schemes from course #{course_id} #{@user_info_str}"

      res = RestClient.get(url, self.http_headers)
      JSON.parse(res.body)
    rescue RestClient::ExceptionWithResponse => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} RestClient error: #{e.response}"
      nil
    rescue StandardError => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} Unexpected error: #{e.message}"
      nil
    end

    # Creates a grade object in a provided course
    # https://docs.valence.desire2learn.com/res/grade.html#post--d2l-api-le-(version)-(orgUnitId)-grades-
    # @param course_id [Integer] ID of the course
    # @param category_id [Integer] ID of the category to assign the grade object to
    # @param name [String] Name of the grade object (default: "Nota de Presença")
    # @param short_name [String] Short name of the grade object (default: "NotaPresenca")
    # @return [Hash, nil] JSON response with created grade object, or nil on error
    def create_grade_object(course_id, category_id, name: nil, short_name: nil)
      url = "#{@base_url}/d2l/api/le/#{@api_versions[:le]}/#{course_id}/grades/"
      @logger.info "[BrightspaceClient] Calling #{url} to create a grade object in course #{course_id} #{@user_info_str}"
      payload = {
        "MaxPoints": 10,
        "CanExceedMaxPoints": false,
        "IsBonus": false,
        "ExcludeFromFinalGradeCalculation": false,
        "GradeSchemeId": nil,
        "Name": name || "Nota de Presença",
        "ShortName": short_name || "NotaPresenca",
        "GradeType": "Numeric",
        "CategoryId": category_id,
        "Description": nil,
        "AssociatedTool": nil,
        "IsHidden": false
      }

      res = RestClient.post(url, payload.to_json, self.http_headers.merge(content_type: :json, accept: :json))
      JSON.parse(res.body)
    rescue RestClient::ExceptionWithResponse => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} RestClient error: #{e.response}"
      nil
    rescue StandardError => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} Unexpected error: #{e.message}"
      nil
    end

    # Updates a grade value for a user in a given course
    # https://docs.valence.desire2learn.com/res/grade.html#put--d2l-api-le-(version)-(orgUnitId)-grades-(gradeObjectId)-values-(userId)
    # @param course_id [Integer] ID of the course
    # @param grade_object_id [Integer] ID of the grade object
    # @param user_id [Integer] ID of the user
    # @param grade_value [Numeric] New grade value to set
    # @return [String, nil] JSON response with updated grade value, or nil on error
    def update_grade_value(course_id, grade_object_id:, user_id:, grade_value:)
      url = "#{@base_url}/d2l/api/le/#{@api_versions[:le]}/#{course_id}/grades/#{grade_object_id}/values/#{user_id}"
      @logger.info "[BrightspaceClient] Calling #{url} to update grade value for user #{user_id}" \
      " in course #{course_id} #{@user_info_str}"

      payload = {
        "GradeObjectType": 1,
        "PointsNumerator": grade_value.to_i,
        "Comments": {
          "Content": "Presença registrada automaticamente via Elos LTI",
          "Type": "Text"
        },
        "PrivateComments": {
          "Content": "",
          "Type": "Text"
        }
      }

      res = RestClient.put(url, payload.to_json, self.http_headers.merge(content_type: :json, accept: :json))
      res.body
    rescue RestClient::ExceptionWithResponse => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} RestClient error: #{e.response}"
      nil
    rescue StandardError => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} Unexpected error: #{e.message}"
      nil
    end

    # Retrieve the enrolled users in the classlist for a provided course
    # https://docs.valence.desire2learn.com/res/enroll.html#get--d2l-api-le-(version)-(orgUnitId)-classlist-paged-
    # The response contains two keys: "Objects" (array of users) and "Next" (URL for the next page, if any)
    # @param course_id [Integer] ID of the course
    # @param next_page_url [String, nil] URL for the next page of results (default: nil)
    # @return [Hash, nil] JSON response with a page of enrolled users, or nil on error
    def get_course_users(course_id, next_page_url: nil)
      first_page_url = "#{@base_url}/d2l/api/le/#{@api_versions[:le]}/#{course_id}/classlist/paged/?onlyShowShownInGrades=true"
      url = next_page_url || first_page_url
      @logger.info "[BrightspaceClient] Calling #{url} to get users enrolled in course #{course_id} #{@user_info_str}"

      res = RestClient.get(url, self.http_headers)
      JSON.parse(res.body)
    rescue RestClient::ExceptionWithResponse => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} RestClient error: #{e.response}"
      nil
    rescue StandardError => e
      @logger.error "[BrightspaceClient##{__method__}]#{@user_info_str} Unexpected error: #{e.message}"
      nil
    end

    # @return [Hash] HTTP headers including the Authorization header
    def http_headers
      { Authorization: "Bearer #{@access_token}" }
    end
  end
end
