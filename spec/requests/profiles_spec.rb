# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Profiles API", type: :request do
  include IdentityFixtures
  include AuthHelpers

  let(:user) { create_onboarded_adult(email: "owner@example.com") }

  describe "GET /api/v1/profiles/me" do
    it "returns own profile with slug and stats" do
      get "/api/v1/profiles/me", headers: headers_for(user)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body.fetch("profile")
      expect(body.dig("details", "slug")).to eq(user.profile.slug)
      expect(body.fetch("stats")).to include("projects_completed", "active_projects", "tasks_approved", "activity")
      expect(body).not_to have_key("date_of_birth")
    end
  end

  describe "PATCH /api/v1/profiles/me" do
    it "updates allowed fields without changing slug" do
      slug = user.profile.slug

      patch "/api/v1/profiles/me",
            params: { display_name: "New Name", bio: "Builder", github_url: "https://github.com/example" },
            headers: headers_for(user),
            as: :json

      expect(response).to have_http_status(:ok)
      details = response.parsed_body.dig("profile", "details")
      expect(details["display_name"]).to eq("New Name")
      expect(details["bio"]).to eq("Builder")
      expect(details["slug"]).to eq(slug)
    end

    it "rejects invalid experience_level" do
      patch "/api/v1/profiles/me",
            params: { experience_level: "expert" },
            headers: headers_for(user),
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/profiles/:slug" do
    it "returns another public adult profile" do
      other = create_onboarded_adult(email: "other@example.com")

      get "/api/v1/profiles/#{other.profile.slug}", headers: headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("profile", "details", "slug")).to eq(other.profile.slug)
    end

    it "returns not_found for age-up pending profiles" do
      other = create_onboarded_adult(email: "pending@example.com")
      other.update!(onboarding_path: "organization_invited")
      other.age_visibility_preference.require_visibility_review!

      get "/api/v1/profiles/#{other.profile.slug}", headers: headers_for(user)

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig("error", "code")).to eq("not_found")
    end

    it "lets the owner read their own restricted profile by slug" do
      user.update!(onboarding_path: "organization_invited")
      user.age_visibility_preference.require_visibility_review!

      get "/api/v1/profiles/#{user.profile.slug}", headers: headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("profile", "details", "slug")).to eq(user.profile.slug)
    end
  end

  describe "POST /api/v1/profiles/me/visibility" do
    it "confirms and reverses public identity" do
      user.update!(onboarding_path: "organization_invited")
      user.age_visibility_preference.require_visibility_review!

      post "/api/v1/profiles/me/visibility",
           params: { decision: "confirm" },
           headers: headers_for(user),
           as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.public_identity_visible?).to eq(true)

      post "/api/v1/profiles/me/visibility",
           params: { decision: "reverse" },
           headers: headers_for(user),
           as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.public_identity_visible?).to eq(false)
    end
  end
end
