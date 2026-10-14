# frozen_string_literal: true

require 'rails_helper'

describe LaunchSigningKey, type: :model do
  # Keys are generated on first use, so a key left behind by anything that touched the
  # test database outside an example makes counting here lie. Inside a transactional
  # example this rolls back with everything else.
  before { described_class.delete_all }

  describe '.current' do
    it 'generates a key when there is none' do
      expect { described_class.current }.to change(described_class, :count).by(1)
    end

    it 'reuses the key it already has' do
      described_class.current

      expect { described_class.current }.not_to change(described_class, :count)
    end

    it 'signs with the newest active key' do
      described_class.generate!
      newest = described_class.generate!

      expect(described_class.current).to eq(newest)
    end

    it 'ignores a key that was retired' do
      retired = described_class.generate!
      retired.update!(active: false)

      expect(described_class.current).not_to eq(retired)
    end
  end

  describe '.key_set' do
    it 'publishes every active key, and only the public half' do
      first = described_class.generate!
      second = described_class.generate!
      described_class.generate!.update!(active: false)

      keys = described_class.key_set[:keys]

      expect(keys.map { |key| key[:kid] }).to match_array([first.kid, second.kid])
      expect(keys.map(&:keys).flatten.uniq).not_to include(:d, :p, :q)
    end

    it 'says what the key is for' do
      described_class.generate!

      key = described_class.key_set[:keys].first

      expect(key[:alg]).to eq('RS256')
      expect(key[:use]).to eq('sig')
      expect(key[:kty]).to eq('RSA')
    end
  end

  describe '#jwk' do
    it 'exports a key that verifies what the private half signed' do
      key = described_class.generate!
      token = JWT.encode({ hello: 'world' }, key.private_rsa, 'RS256', kid: key.kid)

      payload, = JWT.decode(token, nil, true, algorithms: ['RS256'],
                                              jwks: JWT::JWK::Set.new(described_class.key_set))

      expect(payload['hello']).to eq('world')
    end
  end
end
