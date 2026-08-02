# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Independent onboarding", type: :request do
  let(:headers) { auth_headers(firebase_uid: "uid-independent", email: "independent@example.com") }

  def complete_onboarding(payload = independent_onboarding_payload)
    post "/api/v1/onboarding/independent", params: payload, headers: headers, as: :json
  end

  it "completes with a Personal workspace and exactly one trial credit" do
    complete_onboarding

    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body.dig("user", "status")).to eq("active")
    expect(body.dig("user", "age_status")).to eq("adult")
    expect(body.dig("user", "onboarding_path")).to eq("independent")
    expect(body.dig("user", "personal_trial_granted")).to be(true)
    expect(body["workspaces"].map { |workspace| workspace["kind"] }).to eq([ "personal" ])
    expect(body.dig("active_workspace", "kind")).to eq("personal")

    user = User.find_by!(email: "independent@example.com")
    expect(user.personal_workspace).to be_present
    expect(CreditLedgerEntry.where(owner: user, reason: "personal_trial").sum(:amount)).to eq(1)
  end

  it "does not grant a second trial credit when onboarding is retried" do
    complete_onboarding
    expect(response).to have_http_status(:created)

    complete_onboarding

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "code")).to eq("already_onboarded")

    user = User.find_by!(email: "independent@example.com")
    expect(CreditLedgerEntry.where(owner: user, reason: "personal_trial").count).to eq(1)
    expect(Workspace.where(owner_user: user).count).to eq(1)
  end

  it "accepts a submission that omits every optional field" do
    complete_onboarding

    expect(response).to have_http_status(:created)
    profile = User.find_by!(email: "independent@example.com").profile
    expect(profile.bio).to be_nil
    expect(profile.image_url).to be_nil
    expect(profile.github_url).to be_nil
    expect(profile.interests).to eq([])
  end

  it "stores optional fields when provided and caps interests at ten tags" do
    complete_onboarding(
      independent_onboarding_payload(
        bio: "Career switcher into data",
        github_url: "https://github.com/alex",
        interests: (1..15).map { |n| "tag-#{n}" }
      )
    )

    expect(response).to have_http_status(:created)
    profile = User.find_by!(email: "independent@example.com").profile
    expect(profile.bio).to eq("Career switcher into data")
    expect(profile.interests.size).to eq(10)
  end

  it "never persists or returns a date of birth on the independent path" do
    complete_onboarding(independent_onboarding_payload(date_of_birth: "1990-04-01"))

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["profile"]).not_to have_key("date_of_birth")
    expect(User.find_by!(email: "independent@example.com").profile.date_of_birth).to be_nil
  end

  describe "attestation and terms gates" do
    it "rejects a submission without age attestation" do
      complete_onboarding(independent_onboarding_payload(age_attested: false))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/age attestation/i)
      expect(User.find_by(email: "independent@example.com").profile).to be_nil
    end

    it "rejects a submission without terms acceptance" do
      complete_onboarding(independent_onboarding_payload(terms_accepted: false))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/terms/i)
      expect(User.find_by(email: "independent@example.com")).to be_pending_onboarding
    end
  end

  describe "minimum profile validation" do
    it "rejects a missing display name" do
      complete_onboarding(independent_onboarding_payload(display_name: " "))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
    end

    it "rejects an experience level outside the allowed values" do
      complete_onboarding(independent_onboarding_payload(experience_level: "expert"))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/beginner, intermediate, advanced/)
    end

    it "rejects a target role that is neither a taxonomy term nor other text" do
      payload = independent_onboarding_payload
      payload.delete(:target_role_term_id)
      complete_onboarding(payload)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/target role/i)
    end

    it "accepts free text when the user picks the Other role" do
      complete_onboarding(
        independent_onboarding_payload(
          current_role_term_id: role_term("other").id,
          current_role_other: "Museum educator"
        )
      )

      expect(response).to have_http_status(:created)
      expect(User.find_by!(email: "independent@example.com").profile.current_role_other).to eq("Museum educator")
    end

    it "rejects a role term id that does not belong to the roles taxonomy" do
      complete_onboarding(independent_onboarding_payload(target_role_term_id: goal_term.id))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/not a known role/)
    end
  end
end
