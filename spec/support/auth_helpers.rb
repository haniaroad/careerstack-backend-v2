# frozen_string_literal: true

# Stub-mode Firebase tokens. FirebaseTokenVerifier accepts "test:<uid>:<email>"
# in the test environment so specs never need Firebase credentials.
module AuthHelpers
  def stub_token(firebase_uid:, email:, platform_admin: false, auth_time: nil)
    token = "test:#{firebase_uid}:#{email}"
    token = "#{token}:platform_admin" if platform_admin
    token = "#{token}:#{auth_time.to_i}" if auth_time
    token
  end

  def auth_headers(firebase_uid:, email:, platform_admin: false, auth_time: nil)
    { "Authorization" => "Bearer #{stub_token(firebase_uid: firebase_uid, email: email, platform_admin: platform_admin, auth_time: auth_time)}" }
  end

  def headers_for(user, platform_admin: false, auth_time: nil)
    auth_headers(firebase_uid: user.firebase_uid, email: user.email, platform_admin: platform_admin, auth_time: auth_time)
  end

  def staff_headers(user, auth_time: nil)
    headers_for(user, platform_admin: true, auth_time: auth_time)
  end
end

RSpec.configure do |config|
  config.include AuthHelpers
end
