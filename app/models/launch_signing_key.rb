# frozen_string_literal: true

# The RSA key pair this application signs engagement dashboard launch tokens with.
#
# The private half never leaves here; the public half is published as a JWK set, so the
# dashboard can check a signature without ever holding a key able to produce one.
#
# More than one key can be active at a time. Every active key is published, and each
# token names the key that signed it in its `kid` header, so a key can be replaced
# without a window in which tokens already in flight stop verifying. It also means two
# processes generating a key at the same time is harmless: both end up published, and
# both verify.
class LaunchSigningKey < ApplicationRecord
  ALGORITHM = 'RS256'
  KEY_SIZE = 2048

  scope :active, -> { where(active: true) }

  # The key new tokens are signed with. Generated on first use so that no deploy step
  # and no secret of its own are needed to turn the integration on.
  def self.current
    active.order(created_at: :desc).first || generate!
  end

  def self.generate!
    rsa = OpenSSL::PKey::RSA.generate(KEY_SIZE)

    create!(
      kid: JWT::JWK.new(rsa).kid,
      private_key: rsa.to_pem,
      public_key: rsa.public_key.to_pem
    )
  end

  # What the JWKS endpoint serves. Only the public halves are ever in here.
  def self.key_set
    { keys: active.order(created_at: :desc).map(&:jwk) }
  end

  def private_rsa
    OpenSSL::PKey::RSA.new(private_key)
  end

  def public_rsa
    OpenSSL::PKey::RSA.new(public_key)
  end

  # `alg` and `use` are not strictly required, but they tell a consumer what the key is
  # for without it having to guess from the token it is holding.
  def jwk
    JWT::JWK.new(public_rsa).export.symbolize_keys.merge(kid: kid, alg: ALGORITHM, use: 'sig')
  end
end
