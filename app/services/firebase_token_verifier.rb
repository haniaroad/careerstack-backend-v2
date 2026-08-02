# frozen_string_literal: true

require "net/http"
require "json"

# Verifies the bearer credential on protected requests and reduces it to the
# verified Firebase identity (D-1). Rails never trusts a client-supplied user id.
#
# Two modes:
#   * Real mode verifies a Firebase ID token as RS256 against Google's JWKS,
#     checking issuer and audience against FIREBASE_PROJECT_ID.
#   * Stub mode accepts "test:<firebase_uid>:<email>" so local and CI runs do not
#     need Firebase credentials. It is refused in production regardless of env.
class FirebaseTokenVerifier
  class VerificationError < StandardError; end

  JWKS_URL = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"
  JWKS_CACHE_TTL = 1.hour
  STUB_PREFIX = "test:"
  BEARER_PREFIX = "Bearer "

  Identity = Struct.new(:firebase_uid, :email, keyword_init: true)

  class << self
    def verify!(authorization_header)
      new.verify!(authorization_header)
    end

    def stub_mode?
      return false if Rails.env.production?

      configured = ENV["FIREBASE_AUTH_STUB"]
      return ActiveModel::Type::Boolean.new.cast(configured) if configured.present?

      # Default on for test, and for development until a project is configured.
      Rails.env.test? || ENV["FIREBASE_PROJECT_ID"].blank?
    end

    def reset_jwks_cache!
      @jwks_cache = nil
      @jwks_fetched_at = nil
    end

    def jwks
      if @jwks_cache.nil? || @jwks_fetched_at.nil? || @jwks_fetched_at < JWKS_CACHE_TTL.ago
        @jwks_cache = fetch_jwks
        @jwks_fetched_at = Time.current
      end

      @jwks_cache
    end

    private

    def fetch_jwks
      response = Net::HTTP.get_response(URI(JWKS_URL))
      raise VerificationError, "Unable to fetch Firebase signing keys" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise VerificationError, "Unable to fetch Firebase signing keys: #{e.class}"
    end
  end

  def verify!(authorization_header)
    token = extract_bearer_token(authorization_header)
    raise VerificationError, "Missing bearer token" if token.blank?

    self.class.stub_mode? ? verify_stub(token) : verify_firebase_id_token(token)
  end

  private

  def extract_bearer_token(header)
    value = header.to_s.strip
    return nil if value.blank?

    value.start_with?(BEARER_PREFIX) ? value.delete_prefix(BEARER_PREFIX).strip.presence : nil
  end

  def verify_stub(token)
    raise VerificationError, "Invalid stub token" unless token.start_with?(STUB_PREFIX)

    _prefix, firebase_uid, email = token.split(":", 3)
    if firebase_uid.blank? || email.blank?
      raise VerificationError, "Stub token must be test:<firebase_uid>:<email>"
    end

    build_identity(firebase_uid: firebase_uid, email: email)
  end

  def verify_firebase_id_token(token)
    project_id = ENV["FIREBASE_PROJECT_ID"].to_s.strip
    raise VerificationError, "FIREBASE_PROJECT_ID is not configured" if project_id.blank?

    payload, = JWT.decode(
      token,
      nil,
      true,
      algorithms: [ "RS256" ],
      jwks: self.class.jwks,
      iss: "https://securetoken.google.com/#{project_id}",
      verify_iss: true,
      aud: project_id,
      verify_aud: true,
      verify_expiration: true,
      verify_iat: true
    )

    raise VerificationError, "Token subject is missing" if payload["sub"].blank?
    raise VerificationError, "Token email is not verified" unless payload["email_verified"]

    build_identity(firebase_uid: payload["sub"], email: payload["email"])
  rescue JWT::DecodeError => e
    raise VerificationError, "Token verification failed: #{e.message}"
  end

  def build_identity(firebase_uid:, email:)
    normalized_email = email.to_s.strip.downcase
    raise VerificationError, "Token email is missing" if normalized_email.blank?

    Identity.new(firebase_uid: firebase_uid.to_s, email: normalized_email)
  end
end
