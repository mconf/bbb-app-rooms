require 'faraday'
require 'active_support/core_ext'
require 'securerandom'
require 'tempfile'
require 'json'

module Mconf
  module Eduplay
    THUMBNAIL_PATH = Rails.root.join('themes/rnp/assets/images/eduplay-thumbnail.png').to_s
    THUMBNAIL_MIME = 'image/png'
    PRIVACY = { # only 1 and 3 for channels
      public: 1,
      public_not_visible: 2,
      authenticated_access: 3,
      private_with_password: 4
    }.freeze

    class InvalidMethodError
    end

    class API
      def initialize(token)
        @host_url = Rails.application.config.omniauth_eduplay_url
        @token = token
        @client_key = Rails.application.config.omniauth_eduplay_secret
      end

      def self.authorize_path(recordingid)
        Rails.logger.info("[AUTHORIZE_PATH] authorize_path pass")
        query = {
          response_type: 'code',
          client_id: Rails.application.config.omniauth_eduplay_key,
          scope: 'ws:write',
          redirect_uri: Rails.application.config.omniauth_eduplay_redirect_callback,
          state: recordingid,
          nonce: recordingid
        }.to_query

        authorize_url = "#{Rails.application.config.omniauth_eduplay_url}/api/v1/oauth2/authorize"

        "#{authorize_url}?#{query}"
      end

      def self.get_access_token(code)
        Rails.logger.info("[GET_ACCESS_TOKEN] pass")
        token_url = "#{Rails.application.config.omniauth_eduplay_url}/api/v1/oauth2/token"

        response = Faraday.send(
          :post,
          token_url,
          {
            client_id: Rails.application.config.omniauth_eduplay_key,
            redirect_uri: Rails.application.config.omniauth_eduplay_redirect_callback,
            grant_type: 'authorization_code',
            client_secret: Rails.application.config.omniauth_eduplay_secret,
            code: code
          },
          {
            'Content-Type': 'application/x-www-form-urlencoded'
          }
        )
        JSON.parse(response.body)
      end

      def create_video(data, video_data)
        path = "api/v1/videos/#{data['identifier']}?status=0"

        thumbnail = video_data[:thumbnail]
        if video_data[:thumbnail].nil?
          thumbnail = [THUMBNAIL_PATH, THUMBNAIL_MIME]
        end

        payload = {
          image: thumbnail,
          data: {
            title: video_data[:title],
            mediaFileName: data['filename'],
            internalMediaFileName: data['internalMediaFileName'] + '.mp4',
            description: video_data[:description],
            visibility: video_data[:public],
            privatePassword: video_data[:video_password],
            geolocationControl: 1,
            tags: video_data[:tags],
            idsChannels: [video_data[:channel_id]]
          }
        }

        response = upload_request(path, payload)

        JSON.parse(response.body)
      end

      def get_channels
        path = 'api/v1/users/channels'

        request_and_parse(:get, path)
      end

      def create_channel(name, visibility, tags)
        path = 'api/v1/channels'

        payload = {
          data: {
            name: name,
            visibility: visibility,
            tags: tags
          }
        }

        create_multiple_tags(tags)

        response = upload_request(path, payload)

        JSON.parse(response.body)
      end

      def get_tags(term, quantity = 1)
        path = "api/v1/catalog-topics"
        params = { term: term, quantity: quantity }

        request_and_parse(:get, path, params)
      end

      def create_multiple_tags(tags)
        tags = tags.uniq
        threads = tags.map do |tag|
          Thread.new do
            existing_tags = get_tags(tag)
            unless existing_tags[0].eql?(tag)
              Resque.logger.info "Creating tag '#{tag}' ..."
              create_tag(tag)
            else
              Resque.logger.info "Tag '#{tag}' already exists, skipping ..."
            end
          end
        end
        threads.each(&:join)
      end

      def create_tag(tag)
        path = "api/v1/catalog-topics"
        body = { name: tag }

        request_and_parse(:post, path, {}, body)
      end

      def get_upload_link(filename = nil, file_extension = nil)
        filename = "#{filename}#{file_extension || '.mp4'}"

        path = "api/v1/videos/upload-url"
        params = { mediaFileName: filename }

        json = request_and_parse(:get, path, params)

        json.merge({ 'filename' => filename })
      end

      def upload_file(path, filename, mime_type = nil)
        response = upload_request path, file: [filename, mime_type]

        JSON.parse(response.body)
      end

      def download_file(path)
        response = Faraday.get(path)

        tempfile = Tempfile.new(['recording', ".mp4"], binmode: true)
        tempfile.write(response.body)
        tempfile.rewind

        tempfile
      end

      private
      def headers
        headers = {
          "Accept" => "*/*",
          "Authorization" => "Bearer #{@token}"
        }
      end

      def request_and_parse(method, path, params = {}, body = {})
        raise InvalidMethodError unless %i[get post].include?(method)

        query_string = params.empty? ? "" : "?#{URI.encode_www_form(params)}"
        req_headers = headers
        req_headers = req_headers.merge('Content-Type' => 'application/json') if method.eql?(:post)
        body = body.to_json unless body.empty?

        response = Faraday.send(method, "#{@host_url}/#{path}#{query_string}", body, req_headers)

        response.body.empty? ? "" : JSON.parse(response.body)
      end

      def upload_request(path, body)
        url = @host_url

        if path.match(/^https?/)
          u = URI.parse(path)
          url = "#{u.scheme}://#{u.host}"
          path = "#{u.path}?#{u.query}"
        end

        opt = {
          url: url,
          headers: headers
        }

        conn = Faraday.new(opt) do |f|
          f.request :multipart
          f.request :url_encoded
          f.adapter :net_http
        end

        payload = body.map do |k, v|
          if v.kind_of?(Array)
            [k, Faraday::UploadIO.new(v[0], v[1])]
          else
            [k, Faraday::Multipart::ParamPart.new(v.to_json, 'application/json')]
          end
        end

        conn.post(path, payload.to_h)
      end
    end
  end
end
