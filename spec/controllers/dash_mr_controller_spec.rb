# frozen_string_literal: true

require 'rails_helper'

describe DashMrController, type: :controller do
  # The form this renders is the whole point of the action
  render_views

  let(:consumer_config) { FactoryBot.create(:consumer_config, institution_guid: 'guid-1', allow_dash_mr: true) }
  let(:room) { FactoryBot.create(:room, handler: 'handler-1', consumer_key: consumer_config.key) }
  let(:moderator) do
    User.new(uid: 'u-42', full_name: 'Carla Menezes', email: 'carla@escola.edu', roles: 'Instructor')
  end
  let(:student) { User.new(uid: 'u-43', full_name: 'Ana Silva', roles: 'Learner') }

  # What is under test is what the actions do, not how the launch finds the room
  def sign_in_as(user)
    allow(controller).to receive(:find_app_launch)
    allow(controller).to receive(:find_user) { controller.instance_variable_set(:@user, user) }
  end

  before do
    allow(Rails.configuration).to receive(:dash_mr_launch_url).and_return('http://dash.test/launch')
    # The key set published is whatever is stored, so a stray key from outside the
    # example would show up in the response alongside the one under test.
    LaunchSigningKey.delete_all
  end

  describe '#jwks' do
    it 'serves the active public keys' do
      key = LaunchSigningKey.generate!

      get :jwks

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['keys'].map { |k| k['kid'] }).to eq([key.kid])
    end

    it 'needs no room and no user' do
      get :jwks

      expect(response).to have_http_status(:ok)
    end
  end

  describe '#launch' do
    it 'renders the form that posts the token to the dashboard' do
      sign_in_as(moderator)

      get :launch, params: { id: room.handler }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('http://dash.test/launch')
      expect(response.body).to include('name="id_token"')
    end

    it 'turns a student away' do
      sign_in_as(student)

      get :launch, params: { id: room.handler }

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include('name="id_token"')
    end

    it 'turns away a request that carries no room session' do
      get :launch, params: { id: room.handler }

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include('name="id_token"')
    end

    it 'sends nobody to a dashboard that was never configured' do
      sign_in_as(moderator)
      allow(Rails.configuration).to receive(:dash_mr_launch_url).and_return('')

      get :launch, params: { id: room.handler }

      expect(response).to redirect_to(room_path(room))
    end

    # Hiding the button is not a check: the route answers whoever asks for it
    it 'turns away a room whose institution was not enabled' do
      disabled = FactoryBot.create(:consumer_config, institution_guid: 'guid-2', allow_dash_mr: false)
      other_room = FactoryBot.create(:room, handler: 'handler-2', consumer_key: disabled.key)
      sign_in_as(moderator)

      get :launch, params: { id: other_room.handler }

      expect(response).to redirect_to(room_path(other_room))
      expect(response.body).not_to include('name="id_token"')
    end
  end
end
