require 'faraday'
require 'active_support/core_ext'
require 'securerandom'
require 'tempfile'
require 'json'

module Mconf
  module Filesender

    def flatten(a, p = nil)
      o = []
      a.sort.to_h.each do |k, v|
        if v.is_a?(Hash)
          flatten(v, p ? "#{p}[#{k}]" : k).each { |s| o << s }
        else
          o << "#{p ? "#{p}[#{k}]" : k}=#{v}"
        end
      end
      o
    end

    class API
      # $base_url base url to Filesender's rest service
      # $mode authentication mode, "application" or "user"
      # $application_or_uid the application name or user uid
      # $secret signing secret
      def initialize(base_url, mode, application_or_uid, secret)
        raise ArgumentError, 'Missing application id' unless
          base_url.present? &&
          mode.present? &&
          ['application', 'user', 'oauth'].include?(mode) &&
          application_or_uid.present?
    
        @base_url = base_url
        @mode = mode
        @application_or_uid = application_or_uid
        @secret = application_or_uid
        @chunk_size = nil;

      end

      def self.authorize_path(recordingid)
        Rails.logger.info("[AUTHORIZE_PATH] authorize_path pass")
        query = {
          client_id: Rails.application.config.filesender_client_id,
          redirect_uri: Rails.application.config.filesender_redirect_callback,
          response_type: 'code',
          scope: '',
          state: recordingid
        }.to_query

        authorize_url = "#{Rails.application.config.filesender_service_url}/oauth/authorize"

        "#{authorize_url}?#{query}"
      end

      # Take the token from the current user if already logged in
      def self.get_access_token(code)
        Rails.logger.info("[GET_ACCESS_TOKEN] pass")
        token_url = "#{Rails.application.config.filesender_service_url}/oauth/token"

        response = Faraday.post(token_url, {
          grant_type: 'authorization_code',
          client_id: Rails.application.config.filesender_client_id,
          client_secret: Rails.application.config.filesender_client_secret,
          redirect_uri: Rails.application.config.filesender_redirect_callback,
          code: code
        }, {'Content-Type': 'application/x-www-form-urlencoded'})

        JSON.parse(response.body)
      end

      # Take the refresh token to get new access token
      def self.refresh_token(refresh_token)
        Rails.logger.info("[GET_ACCESS_TOKEN] pass")
        token_url = "#{Rails.application.config.filesender_service_url}/oauth/token"

        response = Faraday.post(token_url, {
          grant_type: 'refresh_token',
          client_id: Rails.application.config.filesender_client_id,
          client_secret: Rails.application.config.filesender_client_secret,
          refresh_token: refresh_token
        }, {'Content-Type': 'application/x-www-form-urlencoded'})

        JSON.parse(response.body)
      end

      def _response_header(o, h)
        Rails.logger.info("RESPONSE_HEADER pass")
        name, value = h.split(':').map(&:strip)
        headers[name] = value if name.present?
        h.length
      end

      # Create a request for the filesender API
      def call(method, path, args = {}, content = nil, options = {})
        args.stringify_keys!
        Rails.logger.info("[CALL] pass")
        raise Exception.new('Method is not allowed') unless %w(get post put delete).include? method

        path = "/#{path}" unless path.start_with?('/')
        raise Exception.new('Endpoint is missing') if path == '/'

        content_type = 'application/json'
        content_type = options['Content-Type'] if options.key?('Content-Type')
        
        # If path is /info, then the request is not signed
        if path.include?('/info')
          url = "#{@base_url}#{path}"
        else
          args['oauth_token'] = @application_or_uid

          # Terms of use of the RNP service
          args['aup_checked'] = 1
          args['timestamp'] = Time.now.to_i

          args = args.sort.to_h
      
          signed = "#{method}&#{URI.parse(@base_url).to_s.delete_prefix('https://')}#{path}"
          signed += "?#{args.map { |k, v| "#{k}=#{v}" }.join('&') }"

          if content.present?
            input = content_type == 'application/json' ? content.to_json : content
            signed += "&#{input}"
          end

          args['signature'] = OpenSSL::HMAC.hexdigest('sha1', @secret, signed)

          args = args.sort.to_h
          url = "#{@base_url}#{path}?#{args.map { |k, v| "#{k}=#{v}" }.join('&')}"
        end

        # Set the headers
        headers = {
          'Accept': 'application/json',
          'Content-Type': content_type
        }

        # Basic authentication (remove if the service is not protected in hmg)
        # filesender_enabled = Rails.application.config.filesender_enabled
        # filesender_basic_user = Rails.application.config.filesender_basic_user
        # filesender_basic_password = Rails.application.config.filesender_basic_password

        # Request to Filesender api
        Rails.logger.info("[CALL] url: #{url}")

        case method
        when 'post'
          response = Faraday.post(url, input, headers)
        when 'put'
          response = Faraday.put(url, input, headers)
        when 'delete'
          response = Faraday.delete(url, nil, headers)
        else
          response = Faraday.get(url, nil, headers)
        end

        if response.status != 200
          if method != 'post' || response.status != 201
            raise Exception.new("Http error #{response.status} : #{response.body}")
          end
        end

        raise Exception.new('Empty response') if response.body.blank?

        response = JSON.parse(response.body)
        Rails.logger.info("[CALL] response: #{response}")
      
        if method != 'post'
          response
        else
          OpenStruct.new(location: response['Location'], created: response)
        end
      end

      def get(path, args = {}, options = {})
        options ||= {}
        args ||= {}
        call('get', path, args, options)
      end

      def post(path, args = {}, content = nil, options = {})
        Rails.logger.info("[POST] pass")
        options ||= {}
        args ||= {}
        call('post', path, args, content, options)
      end
      
      def put(path, args = {}, content = nil, options = {})
        Rails.logger.info("[PUT] pass")
        options ||= {}
        args ||= {}
        call('put', path, args, content, options)
      end
      
      def delete(path, args = {}, options = {})
        Rails.logger.info("[DELETE] pass")
        options ||= {}
        args ||= {}
        call('delete', path, args, options)
      end
      
      def get_info
        get('/info')
      end

      def post_transfer(user_id, from, files, recipients, subject = nil, message = nil, expires = nil, options = {})
        Rails.logger.info("[POST_TRANFER] pass")
        options ||= {}
        recipients = [recipients] unless recipients.is_a?(Array)

        if !expires
          info = get_info
          if !info['default_transfer_days_valid']
            raise 'Expires missing and not default value in info to build it from'
          end
          expires = Time.now + info['default_transfer_days_valid'].to_i.days
        end

        post('/transfer', { remote_user: user_id }, {
          from: from,
          files: files,
          recipients: recipients,
          subject: subject,
          message: message,
          expires: expires.to_i,
          options: options,
          aup_checked: true
        })
      end

      def post_chunk(file, chunk)
        Rails.logger.info("[POST_CHUNK] post_chunk pass")
        post(
          "/file/#{file['id']}/chunk",
          { key: file['uid'] },
          chunk,
          { 'Content-Type' => 'application/octet-stream' }
        )
      end
      
      def put_chunk(file, chunk, offset)
        Rails.logger.info("[PUT_CHUNK] put_chunk pass")
        put(
          "/file/#{file['id']}/chunk/#{offset}",
          { key: file['uid'] },
          chunk,
          { 'Content-Type' => 'application/octet-stream' }
        )
      end

      def file_complete(file)
        put(
          "/file/#{file['id']}",
          { key: file['uid'] },
          { complete: true }
        )
      end
      
      def transfer_complete(transfer)
        Rails.logger.info("[TRANSFER_COMPLETE] transfer_complete pass")
        put(
          "/transfer/#{transfer['id']}",
          { key: transfer['files'][0]['uid'] },
          { complete: true }
        )
      end
      
      def delete_transfer(transfer)
        Rails.logger.info("[DELETE TRANSFER] delete_transfer pass")
        id = transfer.is_a?(Integer) ? transfer : transfer['id']
      
        args = {}
        args[:key] = transfer['files'][0]['uid'] if transfer.is_a?(Object)

        delete("/transfer/#{id}", args)
      end

      def send_files(user_id, from, filespath, recipients, subject = nil, message = nil, expires = nil, options = {})
        Rails.logger.info("[SEND_FILES] pass")
        options ||= {}

        info = get_info
        Rails.logger.info("[SEND_FILES] info: #{info}")
        upload_chunk_size = info['upload_chunk_size'].to_i
        
        unless @chunk_size && expires
          expires ||= info.default_transfer_days_valid.days.from_now.to_i
          @chunk_size ||= upload_chunk_size
        end
          
        @chunk_size ||= upload_chunk_size
          
        files = {}
        Array(filespath).each do |path|
          unless File.file?(path)
            raise Exception.new("Not a file path: #{path.inspect}")
          end

          name = File.basename(path)
          size = File.size(path)
          files["#{name}:#{size}"] = {
            name: name,
            size: size,
            path: path
          }
        end

        Rails.logger.info "[SEND_FILES] files: #{files}"
        Rails.logger.info files.values.map { |file| { name: file[:name], size: file[:size] } }

        recipients = Array(recipients)

        transfer = post_transfer(user_id, from, files.values.map { |file| { name: file[:name], size: file[:size] } }, recipients, subject, message, expires, options).created


        Rails.logger.info("[SEND_FILES] after post transfer")
        begin
          transfer['files'].each do |file|
            path = files["#{file['name']}:#{file['size']}"][:path]
            size = files["#{file['name']}:#{file['size']}"][:size]

            File.open(path, 'rb') do |fh|
              (0..size).step(@chunk_size) do |offset|
                data = fh.read(@chunk_size)
                put_chunk(file, data, offset)
              end
            end
            Rails.logger.info("[SEND_FILES] complete")

            file_complete(file)
          end

          transfer_complete(transfer)
        rescue Exception => e
          delete_transfer(transfer)
          raise e
        end

      end

      def download_file path
        Rails.logger.info("[DOWNLOAD_FILE] pass")
        response = Faraday.get(path)

        tempfile = Tempfile.new(['recording', ".mp4"], binmode: true)
        tempfile.write(response.body)
        tempfile.rewind

        tempfile
      end

      def headers
        Rails.logger.info("[HEADERS] pass")
        headers = {
          "Accept" => "application/json",
          "Authorization" => "Bearer #{@token}",
          "clientkey" => @application_or_uid
        }
      end

      def send_file(token, fpath, data, user)
        data.stringify_keys!
        Rails.logger.info("[SEND_FILE] pass")
        client_secret = Rails.application.config.filesender_client_secret
        begin
          access_token = token
          c = self
          info = c.get_info()
          user_id = nil
          from = user[:email]
          filepath = fpath
          recipients = data['recipients']
          subject = data['subject']
          message = data['message']
          expires = Time.now + 10 * 24 * 3600
          options = ["aup_checked"]
          result = c.send_files(user_id, from, filepath, recipients, subject, message, expires, options)
          return { 'result': result }.to_json
          Rails.logger.info("[SEND_FILE] result: #{result}")
        rescue Exception => e
          Rails.logger.error("[+++] FILESENDER EXCEPTION [+++] #{e.message}")
          Rails.logger.error("EXCEPTION #{e.backtrace.join("\n")}")
        end
      end    
    end
  end
end
