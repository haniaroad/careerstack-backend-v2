# frozen_string_literal: true

module PlatformAdmin
  # Firebase custom claims can only be written with the Admin SDK. Stub and
  # local runs record the intent; the operator sets the claim out of band and
  # the person signs in again so the ID token includes it.
  class Claims
    def self.sync!(user:, enabled:)
      return if FirebaseTokenVerifier.stub_mode?

      Rails.logger.info({
        event: "platform_admin_claim_required",
        firebase_uid: user.firebase_uid,
        enabled: enabled
      }.to_json)
    end
  end
end
