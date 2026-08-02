# frozen_string_literal: true

# Stub-mode Firebase tokens. FirebaseTokenVerifier accepts "test:<uid>:<email>"
# in the test environment so specs never need Firebase credentials.
module AuthHelpers
  def stub_token(firebase_uid:, email:)
    "test:#{firebase_uid}:#{email}"
  end

  def auth_headers(firebase_uid:, email:)
    { "Authorization" => "Bearer #{stub_token(firebase_uid: firebase_uid, email: email)}" }
  end

  def headers_for(user)
    auth_headers(firebase_uid: user.firebase_uid, email: user.email)
  end
end

RSpec.configure do |config|
  config.include AuthHelpers
end
