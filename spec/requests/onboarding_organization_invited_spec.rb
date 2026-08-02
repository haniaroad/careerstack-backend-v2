# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Organization-invited onboarding", type: :request do
  let(:headers) { auth_headers(firebase_uid: "uid-invited", email: "invited@example.com") }
  let(:organization) { create_organization(name: "Bridge Academy", timezone: "America/New_York") }
  let(:program) { create_program(organization: organization, name: "Spring Cohort") }

  def invited_payload(token, date_of_birth:, **overrides)
    minimum_profile_payload(
      invitation_token: token,
      terms_accepted: true,
      date_of_birth: date_of_birth,
      **overrides
    )
  end

  def complete_onboarding(payload)
    post "/api/v1/onboarding/organization_invited", params: payload, headers: headers, as: :json
  end

  describe "adult invitee" do
    it "joins the organization and receives Personal plus one trial credit" do
      token = issue_invitation(organization: organization, program: program, email: "invited@example.com")

      complete_onboarding(invited_payload(token, date_of_birth: 25.years.ago.to_date.iso8601))

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body.dig("user", "age_status")).to eq("adult")
      expect(body.dig("user", "onboarding_path")).to eq("organization_invited")
      expect(body.dig("user", "personal_trial_granted")).to be(true)
      expect(body["workspaces"].map { |workspace| workspace["kind"] }).to include("personal", "organization")

      user = User.find_by!(email: "invited@example.com")
      membership = user.organization_memberships.sole
      expect(membership.organization).to eq(organization)
      expect(membership.program).to eq(program)
      expect(membership.role).to eq("participant")
      expect(CreditLedgerEntry.where(owner: user, reason: "personal_trial").sum(:amount)).to eq(1)
    end

    it "honors the role carried by the invitation" do
      token = issue_invitation(organization: organization, role: OrganizationMembership::MANAGER)

      complete_onboarding(invited_payload(token, date_of_birth: 30.years.ago.to_date.iso8601))

      expect(response).to have_http_status(:created)
      expect(User.find_by!(email: "invited@example.com").organization_memberships.sole.role).to eq("manager")
      expect(response.parsed_body["can_access_org_admin"]).to be(false), "Personal is active, so org admin is not in context"
    end
  end

  describe "minor invitee" do
    it "joins the organization privately without Personal or a trial credit" do
      token = issue_invitation(organization: organization, program: program)

      complete_onboarding(invited_payload(token, date_of_birth: 14.years.ago.to_date.iso8601))

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body.dig("user", "age_status")).to eq("minor")
      expect(body.dig("user", "personal_trial_granted")).to be(false)
      expect(body.dig("user", "public_identity_visible")).to be(false)
      expect(body["workspaces"].map { |workspace| workspace["kind"] }).to eq([ "organization" ])
      expect(body.dig("active_workspace", "kind")).to eq("organization")

      user = User.find_by!(email: "invited@example.com")
      expect(user.personal_workspace).to be_nil
      expect(CreditLedgerEntry.where(owner: user)).to be_empty
      expect(user.organization_memberships.sole.organization).to eq(organization)
    end

    it "refuses registration below the minimum age of 13" do
      token = issue_invitation(organization: organization)

      complete_onboarding(invited_payload(token, date_of_birth: 11.years.ago.to_date.iso8601))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("below_minimum_age")
      expect(User.find_by(email: "invited@example.com").organization_memberships).to be_empty
      expect(Invitation.find_by_raw_token(token)).to be_usable
    end
  end

  describe "date of birth privacy" do
    it "stores the date of birth but keeps it out of every response" do
      token = issue_invitation(organization: organization)
      date_of_birth = "2011-06-15"

      complete_onboarding(invited_payload(token, date_of_birth: date_of_birth))
      expect(response).to have_http_status(:created)
      expect(response.body).not_to include(date_of_birth)
      expect(response.parsed_body["profile"]).not_to have_key("date_of_birth")

      user = User.find_by!(email: "invited@example.com")
      expect(user.profile.date_of_birth).to eq(Date.parse(date_of_birth))

      get "/api/v1/session", headers: headers
      expect(response.body).not_to include(date_of_birth)
      expect(response.parsed_body["profile"]).not_to have_key("date_of_birth")
      expect(response.parsed_body.dig("user", "age_status")).to be_present
    end

    it "omits the date of birth from a direct profile serialization" do
      token = issue_invitation(organization: organization)
      complete_onboarding(invited_payload(token, date_of_birth: "2011-06-15"))

      profile = User.find_by!(email: "invited@example.com").profile
      expect(profile.serializable_hash).not_to have_key("date_of_birth")
      expect(profile.to_json).not_to include("2011-06-15")
    end

    it "rejects a missing date of birth" do
      token = issue_invitation(organization: organization)

      complete_onboarding(invited_payload(token, date_of_birth: nil))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/date_of_birth is required/)
    end

    it "rejects a malformed date of birth" do
      token = issue_invitation(organization: organization)

      complete_onboarding(invited_payload(token, date_of_birth: "06/15/2011"))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/ISO 8601/)
    end

    it "rejects a future date of birth" do
      token = issue_invitation(organization: organization)

      complete_onboarding(invited_payload(token, date_of_birth: 1.year.from_now.to_date.iso8601))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/future/)
    end
  end

  describe "invitation validation" do
    it "rejects an unknown token without creating membership" do
      complete_onboarding(invited_payload("not-a-real-token", date_of_birth: "2000-01-01"))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_invitation")
      expect(OrganizationMembership.count).to eq(0)
    end

    it "rejects an expired token without creating membership" do
      token = issue_invitation(organization: organization, expires_at: 1.day.ago)

      complete_onboarding(invited_payload(token, date_of_birth: "2000-01-01"))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_invitation")
      expect(OrganizationMembership.count).to eq(0)
    end

    it "rejects a token that was already accepted" do
      token = issue_invitation(organization: organization)
      complete_onboarding(invited_payload(token, date_of_birth: "2000-01-01"))
      expect(response).to have_http_status(:created)

      post "/api/v1/onboarding/organization_invited",
           params: invited_payload(token, date_of_birth: "1999-01-01"),
           headers: auth_headers(firebase_uid: "uid-second", email: "second@example.com"),
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_invitation")
    end

    it "marks the invitation accepted by the onboarding user" do
      token = issue_invitation(organization: organization)

      complete_onboarding(invited_payload(token, date_of_birth: "2000-01-01"))

      invitation = Invitation.order(:created_at).last
      expect(invitation.accepted_at).to be_present
      expect(invitation.accepted_by_user).to eq(User.find_by!(email: "invited@example.com"))
    end
  end

  describe "organization timezone boundary" do
    it "treats the 18th birthday as adult from the start of that day in the organization timezone" do
      organization = create_organization(name: "Pacific Program", timezone: "America/Los_Angeles")
      token = issue_invitation(organization: organization)
      local_today = Time.current.in_time_zone("America/Los_Angeles").to_date

      complete_onboarding(invited_payload(token, date_of_birth: (local_today - 18.years).iso8601))

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("user", "age_status")).to eq("adult")
    end

    it "treats the day before the 18th birthday as minor" do
      organization = create_organization(name: "Pacific Program", timezone: "America/Los_Angeles")
      token = issue_invitation(organization: organization)
      local_today = Time.current.in_time_zone("America/Los_Angeles").to_date

      complete_onboarding(invited_payload(token, date_of_birth: (local_today - 18.years + 1.day).iso8601))

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("user", "age_status")).to eq("minor")
    end
  end
end
