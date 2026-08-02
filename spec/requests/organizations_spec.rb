# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Organization creation", type: :request do
  let(:user) { create_onboarded_adult(email: "founder@example.com") }

  def create_org(payload = organization_payload)
    post "/api/v1/organizations", params: payload, headers: headers_for(user), as: :json
  end

  it "makes the creator the first admin and grants three pooled trial credits" do
    create_org

    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body["organization_trial_granted"]).to be(true)
    expect(body.dig("organization", "workspace_id")).to be_present
    expect(body.dig("session", "user", "organization_trial_granted")).to be(true)

    organization = Organization.find(body.dig("organization", "id"))
    expect(organization.organization_memberships.sole).to have_attributes(user: user, role: "admin")
    expect(organization.workspace).to be_present
    expect(CreditLedgerEntry.where(owner: organization, reason: "organization_trial").sum(:amount)).to eq(3)
  end

  it "does not consume a personal credit" do
    create_org

    expect(CreditLedgerEntry.where(owner: user).sum(:amount)).to eq(1)
    expect(CreditLedgerEntry.where("amount < 0")).to be_empty
  end

  it "grants the organization trial only once per adult, ever" do
    create_org
    expect(response).to have_http_status(:created)

    create_org(organization_payload(name: "Second Org"))

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["organization_trial_granted"]).to be(false)

    second_org = Organization.find_by!(name: "Second Org")
    expect(CreditLedgerEntry.where(owner: second_org)).to be_empty
    expect(CreditLedgerEntry.where(actor_user: user, reason: "organization_trial").count).to eq(1)
    expect(second_org.organization_memberships.sole.role).to eq("admin")
  end

  it "stores optional metadata when provided" do
    create_org(
      organization_payload(
        website: "https://bridge.example.com",
        expected_participant_range: "51-200",
        timezone: "America/New_York"
      )
    )

    expect(response).to have_http_status(:created)
    organization = Organization.find(response.parsed_body.dig("organization", "id"))
    expect(organization.website).to eq("https://bridge.example.com")
    expect(organization.expected_participant_range).to eq("51-200")
    expect(organization.timezone).to eq("America/New_York")
  end

  it "defaults the timezone to UTC" do
    create_org

    expect(Organization.find(response.parsed_body.dig("organization", "id")).timezone).to eq("UTC")
  end

  describe "eligibility" do
    it "forbids creation for a minor" do
      minor = create_user(email: "minor@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::MINOR)

      post "/api/v1/organizations", params: organization_payload, headers: headers_for(minor), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
      expect(Organization.count).to eq(0)
    end

    it "forbids creation for an unknown-age user" do
      unknown = create_user(email: "unknown@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::UNKNOWN)

      post "/api/v1/organizations", params: organization_payload, headers: headers_for(unknown), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Organization.count).to eq(0)
    end

    it "rejects creation before onboarding is complete" do
      post "/api/v1/organizations",
           params: organization_payload,
           headers: auth_headers(firebase_uid: "uid-pending", email: "pending@example.com"),
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("onboarding_required")
      expect(Organization.count).to eq(0)
    end
  end

  describe "required fields" do
    it "rejects a missing name" do
      create_org(organization_payload(name: " "))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/name is required/)
    end

    it "rejects a missing state or region" do
      create_org(organization_payload(state_region: nil))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/state_region is required/)
    end

    it "rejects a missing structure" do
      payload = organization_payload
      payload.delete(:structure_term_id)
      create_org(payload)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/structure is required/)
    end

    it "accepts free text for the Other structure" do
      create_org(organization_payload(structure_term_id: structure_term("other").id, structure_other: "Worker cooperative"))

      expect(response).to have_http_status(:created)
      expect(Organization.sole.structure_other).to eq("Worker cooperative")
    end

    it "rejects a primary goal term from the wrong taxonomy" do
      create_org(organization_payload(primary_goal_term_id: role_term.id))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/not a known option/)
    end

    it "rejects an unrecognized timezone" do
      create_org(organization_payload(timezone: "Mars/Olympus_Mons"))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/timezone/)
      expect(Organization.count).to eq(0)
    end
  end
end
