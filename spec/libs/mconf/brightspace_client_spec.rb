require 'rails_helper'

RSpec.describe Mconf::BrightspaceClient do
  let(:base_url) { 'https://example.brightspace.com' }
  let(:access_token) { 'test_access_token_123' }
  let(:api_versions) { { lp: '1.54', le: '1.89' } }
  let(:user_info) { { email: 'test@example.com', launch_nonce: 'nonce123' } }
  let(:logger) { instance_double(Logger) }

  let(:client) do
    described_class.new(
      base_url,
      access_token,
      api_versions: api_versions,
      user_info: user_info,
      logger: logger
    )
  end

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
  end

  describe '#initialize' do
    context 'with valid parameters' do
      it 'creates a client instance' do
        expect(client).to be_a(Mconf::BrightspaceClient)
      end

      it 'logs initialization' do
        expect(logger).to receive(:info).with(
          "[BrightspaceClient] Initialized with base_url=#{base_url} [email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}]"
        )
        client
      end
    end

    context 'with missing base_url' do
      it 'raises ArgumentError' do
        expect {
          described_class.new('', access_token, logger: logger)
        }.to raise_error(ArgumentError, 'Base URL must be provided')
      end
    end

    context 'with missing access_token' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(base_url, '', logger: logger)
        }.to raise_error(ArgumentError, 'Access token must be provided')
      end
    end

    context 'without api_versions' do
      it 'uses default api_versions' do
        client = described_class.new(base_url, access_token, logger: logger)
        expect(client).to be_a(Mconf::BrightspaceClient)
      end
    end

    context 'without user_info' do
      it 'creates a client without user info string' do
        expect(logger).to receive(:info).with(
          "[BrightspaceClient] Initialized with base_url=#{base_url} "
        )
        described_class.new(base_url, access_token, logger: logger)
      end
    end
  end

  describe '#http_headers' do
    it 'returns headers with Authorization Bearer token' do
      headers = client.http_headers
      expect(headers[:Authorization]).to eq("Bearer #{access_token}")
    end
  end

  describe '#get_profile_image' do
    let(:url) { "#{base_url}/d2l/api/lp/#{api_versions[:lp]}/profile/myProfile/image?size=200" }
    let(:image_data) { 'binary_image_data' }

    before do
      allow(logger).to receive(:info).with(
        "[BrightspaceClient] Calling #{url} to get user profile image [email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}]"
      )
    end

    context 'when successful' do
      it 'returns the profile image data' do
        response = double('response', body: image_data)
        expect(RestClient).to receive(:get).with(url, client.http_headers).and_return(response)

        result = client.get_profile_image
        expect(result).to eq(image_data)
      end

      it 'accepts custom size parameter' do
        custom_url = "#{base_url}/d2l/api/lp/#{api_versions[:lp]}/profile/myProfile/image?size=300"
        response = double('response', body: image_data)
        
        allow(logger).to receive(:info)
        expect(RestClient).to receive(:get).with(custom_url, client.http_headers).and_return(response)

        result = client.get_profile_image(size: 300)
        expect(result).to eq(image_data)
      end
    end

    context 'when profile image not found' do
      it 'returns nil and logs info' do
        error = RestClient::NotFound.new
        allow(error).to receive(:message).and_return('404 Not Found')
        
        expect(RestClient).to receive(:get).with(url, client.http_headers).and_raise(error)
        expect(logger).to receive(:info).with(
          "[BrightspaceClient][email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}] Profile image not found, response: 404 Not Found"
        )

        result = client.get_profile_image
        expect(result).to be_nil
      end
    end

    context 'when RestClient exception occurs' do
      it 'returns nil and logs error' do
        error = RestClient::BadRequest.new
        allow(error).to receive(:response).and_return('error response')
        
        expect(RestClient).to receive(:get).with(url, client.http_headers).and_raise(error)
        expect(logger).to receive(:error).with(
          "[BrightspaceClient#get_profile_image][email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}] RestClient error: error response"
        )

        result = client.get_profile_image
        expect(result).to be_nil
      end
    end

    context 'when unexpected error occurs' do
      it 'returns nil and logs error' do
        error = StandardError.new('Unexpected error')
        
        expect(RestClient).to receive(:get).with(url, client.http_headers).and_raise(error)
        expect(logger).to receive(:error).with(
          "[BrightspaceClient#get_profile_image][email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}] Unexpected error: Unexpected error"
        )

        result = client.get_profile_image
        expect(result).to be_nil
      end
    end
  end

  describe '#get_course_grade_objects' do
    let(:course_id) { 12345 }
    let(:url) { "#{base_url}/d2l/api/le/#{api_versions[:le]}/#{course_id}/grades/" }
    let(:grade_objects) { [{ 'Id' => 1, 'Name' => 'Grade Object 1' }] }

    before do
      allow(logger).to receive(:info).with(
        "[BrightspaceClient] Calling #{url} to get grade objects from course #{course_id} [email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}]"
      )
    end

    context 'when successful' do
      it 'returns parsed JSON response' do
        response = double('response', body: grade_objects.to_json)
        expect(RestClient).to receive(:get).with(url, client.http_headers).and_return(response)

        result = client.get_course_grade_objects(course_id)
        expect(result).to eq(grade_objects)
      end
    end

    context 'when RestClient exception occurs' do
      it 'returns nil and logs error' do
        error = RestClient::Unauthorized.new
        allow(error).to receive(:response).and_return('unauthorized')
        
        expect(RestClient).to receive(:get).with(url, client.http_headers).and_raise(error)
        expect(logger).to receive(:error).with(
          "[BrightspaceClient#get_course_grade_objects][email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}] RestClient error: unauthorized"
        )

        result = client.get_course_grade_objects(course_id)
        expect(result).to be_nil
      end
    end

    context 'when unexpected error occurs' do
      it 'returns nil and logs error' do
        error = StandardError.new('Connection timeout')
        
        expect(RestClient).to receive(:get).with(url, client.http_headers).and_raise(error)
        expect(logger).to receive(:error).with(
          "[BrightspaceClient#get_course_grade_objects][email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}] Unexpected error: Connection timeout"
        )

        result = client.get_course_grade_objects(course_id)
        expect(result).to be_nil
      end
    end
  end

  describe '#get_course_grade_categories' do
    let(:course_id) { 12345 }
    let(:url) { "#{base_url}/d2l/api/le/#{api_versions[:le]}/#{course_id}/grades/categories/" }
    let(:grade_categories) { [{ 'CategoryId' => 1, 'Name' => 'Attendance' }] }

    before do
      allow(logger).to receive(:info).with(
        "[BrightspaceClient] Calling #{url} to get grade categories from course #{course_id} [email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}]"
      )
    end

    context 'when successful' do
      it 'returns parsed JSON response' do
        response = double('response', body: grade_categories.to_json)
        expect(RestClient).to receive(:get).with(url, client.http_headers).and_return(response)

        result = client.get_course_grade_categories(course_id)
        expect(result).to eq(grade_categories)
      end
    end

    context 'when error occurs' do
      it 'returns nil and logs error' do
        error = RestClient::InternalServerError.new
        allow(error).to receive(:response).and_return('server error')
        
        expect(RestClient).to receive(:get).with(url, client.http_headers).and_raise(error)
        expect(logger).to receive(:error)

        result = client.get_course_grade_categories(course_id)
        expect(result).to be_nil
      end
    end
  end

  describe '#create_course_grade_category' do
    let(:course_id) { 12345 }
    let(:url) { "#{base_url}/d2l/api/le/#{api_versions[:le]}/#{course_id}/grades/categories/" }
    let(:created_category) { { 'CategoryId' => 99, 'Name' => 'Presença nas aulas online' } }
    let(:expected_payload) do
      {
        "Name": "Presença nas aulas online",
        "ShortName": "Presença nas aulas online",
        "CanExceedMax": false,
        "ExcludeFromFinalGrade": false,
        "StartDate": nil,
        "EndDate": nil,
        "Weight": nil,
        "MaxPoints": Mconf::BrightspaceClient::MaxGrade,
        "AutoPoints": nil,
        "WeightDistributionType": nil,
        "NumberOfHighestToDrop": nil,
        "NumberOfLowestToDrop": nil
      }
    end

    before do
      allow(logger).to receive(:info).with(
        "[BrightspaceClient] Calling #{url} to create a grade category in course #{course_id} [email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}]"
      )
    end

    context 'when successful with default parameters' do
      it 'creates a grade category and returns parsed response' do
        response = double('response', body: created_category.to_json)
        expect(RestClient).to receive(:post).with(
          url,
          expected_payload.to_json,
          client.http_headers.merge(content_type: :json, accept: :json)
        ).and_return(response)

        result = client.create_course_grade_category(course_id)
        expect(result).to eq(created_category)
      end
    end

    context 'when successful with custom name and short_name' do
      it 'creates a grade category with custom parameters' do
        custom_payload = expected_payload.merge(
          "Name": "Custom Category",
          "ShortName": "CustomCat"
        )
        response = double('response', body: created_category.to_json)
        
        expect(RestClient).to receive(:post).with(
          url,
          custom_payload.to_json,
          client.http_headers.merge(content_type: :json, accept: :json)
        ).and_return(response)

        result = client.create_course_grade_category(
          course_id,
          name: "Custom Category",
          short_name: "CustomCat"
        )
        expect(result).to eq(created_category)
      end
    end

    context 'when error occurs' do
      it 'returns nil and logs error' do
        error = RestClient::UnprocessableEntity.new
        allow(error).to receive(:response).and_return('validation error')
        
        expect(RestClient).to receive(:post).and_raise(error)
        expect(logger).to receive(:error)

        result = client.create_course_grade_category(course_id)
        expect(result).to be_nil
      end
    end
  end

  describe '#get_course_grade_schemes' do
    let(:course_id) { 12345 }
    let(:url) { "#{base_url}/d2l/api/le/#{api_versions[:le]}/#{course_id}/grades/schemes/" }
    let(:grade_schemes) { [{ 'SchemeId' => 1, 'Name' => 'Percentage' }] }

    before do
      allow(logger).to receive(:info).with(
        "[BrightspaceClient] Calling #{url} to get grade schemes from course #{course_id} [email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}]"
      )
    end

    context 'when successful' do
      it 'returns parsed JSON response' do
        response = double('response', body: grade_schemes.to_json)
        expect(RestClient).to receive(:get).with(url, client.http_headers).and_return(response)

        result = client.get_course_grade_schemes(course_id)
        expect(result).to eq(grade_schemes)
      end
    end

    context 'when error occurs' do
      it 'returns nil and logs error' do
        error = StandardError.new('Network error')
        
        expect(RestClient).to receive(:get).with(url, client.http_headers).and_raise(error)
        expect(logger).to receive(:error)

        result = client.get_course_grade_schemes(course_id)
        expect(result).to be_nil
      end
    end
  end

  describe '#create_grade_object' do
    let(:course_id) { 12345 }
    let(:category_id) { 99 }
    let(:url) { "#{base_url}/d2l/api/le/#{api_versions[:le]}/#{course_id}/grades/" }
    let(:created_grade_object) { { 'Id' => 101, 'Name' => 'Nota de Presença' } }
    let(:expected_payload) do
      {
        "MaxPoints": Mconf::BrightspaceClient::MaxGrade,
        "CanExceedMaxPoints": false,
        "IsBonus": false,
        "ExcludeFromFinalGradeCalculation": false,
        "GradeSchemeId": nil,
        "Name": "Nota de Presença",
        "ShortName": "NotaPresenca",
        "GradeType": "Numeric",
        "CategoryId": category_id,
        "Description": nil,
        "AssociatedTool": nil,
        "IsHidden": false
      }
    end

    before do
      allow(logger).to receive(:info).with(
        "[BrightspaceClient] Calling #{url} to create a grade object in course #{course_id} [email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}]"
      )
    end

    context 'when successful with default parameters' do
      it 'creates a grade object and returns parsed response' do
        response = double('response', body: created_grade_object.to_json)
        expect(RestClient).to receive(:post).with(
          url,
          expected_payload.to_json,
          client.http_headers.merge(content_type: :json, accept: :json)
        ).and_return(response)

        result = client.create_grade_object(course_id, category_id)
        expect(result).to eq(created_grade_object)
      end
    end

    context 'when successful with custom name and short_name' do
      it 'creates a grade object with custom parameters' do
        custom_payload = expected_payload.merge(
          "Name": "Custom Grade",
          "ShortName": "CustomGrd"
        )
        response = double('response', body: created_grade_object.to_json)
        
        expect(RestClient).to receive(:post).with(
          url,
          custom_payload.to_json,
          client.http_headers.merge(content_type: :json, accept: :json)
        ).and_return(response)

        result = client.create_grade_object(
          course_id,
          category_id,
          name: "Custom Grade",
          short_name: "CustomGrd"
        )
        expect(result).to eq(created_grade_object)
      end
    end

    context 'when error occurs' do
      it 'returns nil and logs error' do
        error = RestClient::Forbidden.new
        allow(error).to receive(:response).and_return('forbidden')
        
        expect(RestClient).to receive(:post).and_raise(error)
        expect(logger).to receive(:error)

        result = client.create_grade_object(course_id, category_id)
        expect(result).to be_nil
      end
    end
  end

  describe '#update_grade_value' do
    let(:course_id) { 12345 }
    let(:grade_object_id) { 101 }
    let(:user_id) { 999 }
    let(:grade_value) { 8.5 }
    let(:url) { "#{base_url}/d2l/api/le/#{api_versions[:le]}/#{course_id}/grades/#{grade_object_id}/values/#{user_id}" }
    let(:expected_payload) do
      {
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
    end

    before do
      allow(logger).to receive(:info).with(
        "[BrightspaceClient] Calling #{url} to assign grade value #{grade_value} to user #{user_id} in course #{course_id} [email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}]"
      )
    end

    context 'when successful with default comment' do
      it 'updates the grade value and returns response body' do
        response = double('response', body: 'success')
        expect(RestClient).to receive(:put).with(
          url,
          expected_payload.to_json,
          client.http_headers.merge(content_type: :json, accept: :json)
        ).and_return(response)

        result = client.update_grade_value(
          course_id,
          grade_object_id: grade_object_id,
          user_id: user_id,
          grade_value: grade_value
        )
        expect(result).to eq('success')
      end
    end

    context 'when successful with custom comment' do
      it 'updates the grade value with custom comment' do
        custom_payload = expected_payload.merge(
          "Comments": {
            "Content": "Custom attendance note",
            "Type": "Text"
          }
        )
        response = double('response', body: 'success')
        
        expect(RestClient).to receive(:put).with(
          url,
          custom_payload.to_json,
          client.http_headers.merge(content_type: :json, accept: :json)
        ).and_return(response)

        result = client.update_grade_value(
          course_id,
          grade_object_id: grade_object_id,
          user_id: user_id,
          grade_value: grade_value,
          grade_comment: "Custom attendance note"
        )
        expect(result).to eq('success')
      end
    end

    context 'when grade_value is a float' do
      it 'converts grade_value to integer' do
        grade_value = 7.8
        payload = expected_payload.merge("PointsNumerator": 7)
        response = double('response', body: 'success')
        
        allow(logger).to receive(:info)
        expect(RestClient).to receive(:put).with(
          url,
          payload.to_json,
          client.http_headers.merge(content_type: :json, accept: :json)
        ).and_return(response)

        result = client.update_grade_value(
          course_id,
          grade_object_id: grade_object_id,
          user_id: user_id,
          grade_value: grade_value
        )
        expect(result).to eq('success')
      end
    end

    context 'when RestClient exception occurs' do
      it 'returns nil and logs error' do
        error = RestClient::BadRequest.new
        allow(error).to receive(:response).and_return('bad request')
        
        expect(RestClient).to receive(:put).and_raise(error)
        expect(logger).to receive(:error).with(
          "[BrightspaceClient#update_grade_value][email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}] RestClient error: bad request"
        )

        result = client.update_grade_value(
          course_id,
          grade_object_id: grade_object_id,
          user_id: user_id,
          grade_value: grade_value
        )
        expect(result).to be_nil
      end
    end

    context 'when unexpected error occurs' do
      it 'returns nil and logs error' do
        error = StandardError.new('Database error')
        
        expect(RestClient).to receive(:put).and_raise(error)
        expect(logger).to receive(:error)

        result = client.update_grade_value(
          course_id,
          grade_object_id: grade_object_id,
          user_id: user_id,
          grade_value: grade_value
        )
        expect(result).to be_nil
      end
    end
  end

  describe '#get_course_users' do
    let(:course_id) { 12345 }
    let(:first_page_url) { "#{base_url}/d2l/api/le/#{api_versions[:le]}/#{course_id}/classlist/paged/?onlyShowShownInGrades=true" }
    let(:users_response) do
      {
        'Objects' => [
          { 'UserId' => 1, 'DisplayName' => 'User 1' },
          { 'UserId' => 2, 'DisplayName' => 'User 2' }
        ],
        'Next' => 'https://example.brightspace.com/next-page'
      }
    end

    context 'when requesting first page' do
      before do
        allow(logger).to receive(:info).with(
          "[BrightspaceClient] Calling #{first_page_url} to get users enrolled in course #{course_id} [email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}]"
        )
      end

      it 'returns parsed JSON response with users and next page URL' do
        response = double('response', body: users_response.to_json)
        expect(RestClient).to receive(:get).with(first_page_url, client.http_headers).and_return(response)

        result = client.get_course_users(course_id)
        expect(result).to eq(users_response)
        expect(result['Objects'].length).to eq(2)
        expect(result['Next']).to eq('https://example.brightspace.com/next-page')
      end
    end

    context 'when requesting next page' do
      let(:next_page_url) { 'https://example.brightspace.com/next-page' }
      let(:next_page_response) do
        {
          'Objects' => [{ 'UserId' => 3, 'DisplayName' => 'User 3' }],
          'Next' => nil
        }
      end

      before do
        allow(logger).to receive(:info).with(
          "[BrightspaceClient] Calling #{next_page_url} to get users enrolled in course #{course_id} [email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}]"
        )
      end

      it 'returns parsed JSON response from next page' do
        response = double('response', body: next_page_response.to_json)
        expect(RestClient).to receive(:get).with(next_page_url, client.http_headers).and_return(response)

        result = client.get_course_users(course_id, next_page_url: next_page_url)
        expect(result).to eq(next_page_response)
        expect(result['Objects'].length).to eq(1)
        expect(result['Next']).to be_nil
      end
    end

    context 'when RestClient exception occurs' do
      before do
        allow(logger).to receive(:info)
      end

      it 'returns nil and logs error' do
        error = RestClient::NotFound.new
        allow(error).to receive(:response).and_return('not found')
        
        expect(RestClient).to receive(:get).with(first_page_url, client.http_headers).and_raise(error)
        expect(logger).to receive(:error).with(
          "[BrightspaceClient#get_course_users][email=#{user_info[:email]}, launch_nonce=#{user_info[:launch_nonce]}] RestClient error: not found"
        )

        result = client.get_course_users(course_id)
        expect(result).to be_nil
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(logger).to receive(:info)
      end

      it 'returns nil and logs error' do
        error = StandardError.new('Parsing error')
        
        expect(RestClient).to receive(:get).with(first_page_url, client.http_headers).and_raise(error)
        expect(logger).to receive(:error)

        result = client.get_course_users(course_id)
        expect(result).to be_nil
      end
    end
  end
end
