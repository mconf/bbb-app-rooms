require 'faraday'
require 'active_support/core_ext'
require 'securerandom'
require 'tempfile'
require 'json'

module Eduplay
  THUMBNAIL_PATH = Rails.root.join('app/assets/images/contato.png').to_s
  THUMBNAIL_MIME = 'image/png'

  class InvalidMethodError
  end

  class API

    def initialize host_url, token, client_key
      @host_url = host_url
      @token = token
      @client_key = client_key
    end

    def self.authorize_path(recordingid)
      Rails.logger.info("[AUTHORIZE_PATH] authorize_path pass")
      query = {
        response_type: 'code',
        client_id: Rails.application.config.eduplay_client_id,
        scope: 'ws:write',
        redirect_uri: Rails.application.config.eduplay_redirect_callback,
        state: recordingid
      }.to_query

      authorize_url = "#{Rails.application.config.eduplay_service_url}/portal/oauth/authorize"

      "#{authorize_url}?#{query}"
    end

    def self.get_access_token(code)
      Rails.logger.info("[GET_ACCESS_TOKEN] pass")
      token_url = "#{Rails.application.config.eduplay_service_url}/portal/oauth/token"

      response = Faraday.send(
        :post,
        token_url,
        {
          client_id: Rails.application.config.eduplay_client_id,
          redirect_uri: Rails.application.config.eduplay_redirect_callback,
          grant_type: 'authorization_code',
          client_secret: Rails.application.config.eduplay_client_secret,
          code: code
        },
        {
          'Content-Type': 'application/x-www-form-urlencoded'
        }
      )
      JSON.parse(response.body)
    end

    def user_info user
      path = "services/user/find/#{user}"

      request_and_parse(:get, path)
    end

    def create_video username, id, filename, opt
      path = "services/video/save/#{id}/#{filename}"

      tempfile = get_xml_file 'video', title: opt[:title], keywords: 'mconf'

      payload = {
        :file => [Eduplay::THUMBNAIL_PATH, Eduplay::THUMBNAIL_MIME],
        :video => [tempfile, 'application/xml'],
        :username => username,
      }

      response = upload_request(path, payload)

      tempfile.close
      tempfile.unlink

      JSON.parse(response.body)
    end

    def get_video id
      path = "services/video/#{id}"

      request_and_parse(:get, path)
    end

    def get_upload_link id = nil, filename = nil, file_extension = nil
      id = id || SecureRandom.uuid
      filename = filename || "#{id}#{file_extension || '.mp4'}"

      path = "services/video/upload/url/#{id}/#{filename}"

      json = request_and_parse(:get, path)

      json.merge({'id' => id, 'filename' => filename})
    end

    def upload_file path, filename, mime_type = nil

      response = upload_request path, file: [filename, mime_type]

      JSON.parse(response.body)
    end

    def download_file path
      response = Faraday.get(path)

      tempfile = Tempfile.new(['recording', ".mp4"], binmode: true)
      tempfile.write(response.body)
      tempfile.rewind

      tempfile
    end

    private
    def headers
      headers = {
        "Accept" => "application/json",
        "Authorization" => "Bearer #{@token}",
        "clientkey" => @client_key
      }
    end

    def request_and_parse method, path, body = {}
      throw InvalidMethodError unless [:get, :post].include?(method)

      response = Faraday.send(method, "#{@host_url}/#{path}", body, headers)

      JSON.parse(response.body)
    end

    def upload_request path, body
      url = @host_url

      if path.match(/^https?/)
        u = URI.parse(path)
        url = "#{u.scheme}://#{u.host}"
        path = "#{u.path}?#{u.query}"
      end

      opt = {
        url: url,
        headers: headers.merge({
          'Content-Type': 'multipart/form-data'
        }),
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
          [k, v]
        end
      end

      conn.post(path, payload.to_h)
    end

    def get_xml_file title, keys
      tempfile = Tempfile.new([title, '.xml'])

      xml = keys.to_xml(skip_instruct: true, root: 'video')

      tempfile.write(xml)
      tempfile.rewind

      tempfile
    end
  end

end