# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Firebase authentication", type: :request do
  describe "public allowlist" do
    it "serves health without a token" do
      get "/health"

      expect(response).to have_http_status(:ok)
    end

    it "serves readiness without a token" do
      get "/ready"

      expect(response).to have_http_status(:ok)
    end

    it "serves the /up alias without a token" do
      get "/up"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "protected endpoints" do
    it "rejects a missing Authorization header with the error envelope" do
      get "/api/v1/session"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to match(
        "error" => hash_including(
          "code" => "unauthenticated",
          "message" => "Authentication required",
          "request_id" => be_present
        )
      )
    end

    it "rejects a bearer credential that fails verification" do
      get "/api/v1/session", headers: { "Authorization" => "Bearer not-a-verifiable-token" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
    end

    it "rejects a token without the Bearer scheme" do
      get "/api/v1/session", headers: { "Authorization" => stub_token(firebase_uid: "uid-1", email: "a@example.com") }

      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts a verified token and bootstraps a pending_onboarding user" do
      expect {
        get "/api/v1/session", headers: auth_headers(firebase_uid: "uid-new", email: "new@example.com")
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("user", "email")).to eq("new@example.com")
      expect(response.parsed_body.dig("user", "status")).to eq("pending_onboarding")
      expect(response.parsed_body.dig("user", "onboarding_complete")).to be(false)
    end

    it "reuses the same account for repeated requests" do
      headers = auth_headers(firebase_uid: "uid-repeat", email: "repeat@example.com")

      get "/api/v1/session", headers: headers
      expect {
        get "/api/v1/session", headers: headers
      }.not_to change(User, :count)
    end
  end

  describe "one account per verified email" do
    it "resolves a new provider uid for a known email to the existing account" do
      existing = create_user(email: "linked@example.com", firebase_uid: "google-uid")

      expect {
        get "/api/v1/session", headers: auth_headers(firebase_uid: "magic-link-uid", email: "linked@example.com")
      }.not_to change(User, :count)

      expect(response).to have_http_status(:ok)
      expect(existing.reload.firebase_uid).to eq("magic-link-uid")
      expect(response.parsed_body.dig("user", "id")).to eq(existing.id)
    end

    it "normalizes token email casing to a single account" do
      user = create_user(email: "casing@example.com")

      expect {
        get "/api/v1/session", headers: auth_headers(firebase_uid: user.firebase_uid, email: "Casing@Example.com")
      }.not_to change(User, :count)

      expect(response.parsed_body.dig("user", "email")).to eq("casing@example.com")
    end
  end

  describe "suspended accounts" do
    it "denies application access even with a valid token" do
      user = create_user(email: "blocked@example.com", status: User::SUSPENDED)

      get "/api/v1/session", headers: headers_for(user)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("account_suspended")
    end

    it "denies write endpoints for suspended accounts" do
      user = create_onboarded_adult(email: "suspendable@example.com")
      user.update!(status: User::SUSPENDED)

      post "/api/v1/organizations", params: organization_payload, headers: headers_for(user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("account_suspended")
      expect(Organization.where(name: "STEM Forward")).to be_empty
    end
  end
end
