# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Invitations", type: :request do
  let(:admin) { create_onboarded_adult(email: "admin@example.com") }
  let(:organization) { create_organization(name: "Bridge Academy") }
  let(:program) { create_program(organization: organization, name: "Spring Cohort") }

  before { create_membership(organization: organization, user: admin, role: OrganizationMembership::ADMIN) }

  describe "POST /api/v1/invitations" do
    it "returns the raw token exactly once and stores only its digest" do
      post "/api/v1/invitations",
           params: { organization_id: organization.id, program_id: program.id, email: "Invitee@Example.com" },
           headers: headers_for(admin),
           as: :json

      expect(response).to have_http_status(:created)
      token = response.parsed_body.dig("invitation", "token")
      expect(token).to be_present

      invitation = Invitation.find(response.parsed_body.dig("invitation", "id"))
      expect(invitation.token_digest).to eq(Invitation.digest(token))
      expect(invitation.token_digest).not_to eq(token)
      expect(invitation.email).to eq("invitee@example.com")
      expect(invitation.program).to eq(program)
      expect(invitation.created_by_user).to eq(admin)
      expect(invitation.attributes).not_to have_key("token")
    end

    it "does not consume any credits" do
      expect {
        post "/api/v1/invitations",
             params: { organization_id: organization.id },
             headers: headers_for(admin),
             as: :json
      }.not_to change(CreditLedgerEntry, :count)
    end

    it "allows a manager to invite" do
      manager = create_onboarded_adult(email: "manager@example.com")
      create_membership(organization: organization, user: manager, role: OrganizationMembership::MANAGER)

      post "/api/v1/invitations",
           params: { organization_id: organization.id },
           headers: headers_for(manager),
           as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a participant from inviting" do
      participant = create_onboarded_adult(email: "participant@example.com")
      create_membership(organization: organization, user: participant)

      post "/api/v1/invitations",
           params: { organization_id: organization.id },
           headers: headers_for(participant),
           as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
    end

    it "forbids a non-member from inviting" do
      outsider = create_onboarded_adult(email: "outsider@example.com")

      post "/api/v1/invitations",
           params: { organization_id: organization.id },
           headers: headers_for(outsider),
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/invitations", params: { organization_id: organization.id }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a program from another organization" do
      other_program = create_program(organization: create_organization(name: "Other Org"))

      post "/api/v1/invitations",
           params: { organization_id: organization.id, program_id: other_program.id },
           headers: headers_for(admin),
           as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "rejects an unknown role" do
      post "/api/v1/invitations",
           params: { organization_id: organization.id, role: "owner" },
           headers: headers_for(admin),
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to match(/role must be one of/)
    end

    it "lets an admin appoint another admin" do
      post "/api/v1/invitations",
           params: { organization_id: organization.id, role: "admin" },
           headers: headers_for(admin),
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("invitation", "role")).to eq("admin")
    end

    it "stops a manager from inviting above their own role" do
      manager = create_onboarded_adult(email: "manager@example.com")
      create_membership(organization: organization, user: manager, role: OrganizationMembership::MANAGER)

      post "/api/v1/invitations",
           params: { organization_id: organization.id, role: "admin" },
           headers: headers_for(manager),
           as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
      expect(Invitation.count).to eq(0)
    end
  end

  describe "GET /api/v1/invitations/:token" do
    it "previews the organization and program for a usable token" do
      token = issue_invitation(organization: organization, program: program, email: "invitee@example.com")

      get "/api/v1/invitations/#{token}", headers: auth_headers(firebase_uid: "uid-preview", email: "invitee@example.com")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["invitation"]).to include(
        "organization_id" => organization.id,
        "organization_name" => "Bridge Academy",
        "program_name" => "Spring Cohort",
        "role" => "participant"
      )
    end

    it "requires authentication" do
      token = issue_invitation(organization: organization)

      get "/api/v1/invitations/#{token}"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the same rejection for unknown and expired tokens" do
      expired = issue_invitation(organization: organization, expires_at: 1.hour.ago)
      headers = auth_headers(firebase_uid: "uid-preview", email: "invitee@example.com")

      get "/api/v1/invitations/#{expired}", headers: headers
      expired_body = response.parsed_body

      get "/api/v1/invitations/does-not-exist", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_invitation")
      expect(response.parsed_body.dig("error", "message")).to eq(expired_body.dig("error", "message"))
    end
  end

  describe "POST /api/v1/invitations/:token/accept" do
    let(:invitee) { create_onboarded_adult(email: "invitee@example.com") }

    it "creates membership and makes the organization workspace available" do
      token = issue_invitation(organization: organization, program: program)

      post "/api/v1/invitations/#{token}/accept", headers: headers_for(invitee), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["workspaces"].map { |workspace| workspace["kind"] }).to include("organization")

      membership = invitee.organization_memberships.sole
      expect(membership.organization).to eq(organization)
      expect(membership.program).to eq(program)
      expect(Invitation.order(:created_at).last.accepted_by_user).to eq(invitee)
    end

    it "does not consume credits" do
      token = issue_invitation(organization: organization)
      accept_headers = headers_for(invitee)

      expect {
        post "/api/v1/invitations/#{token}/accept", headers: accept_headers, as: :json
      }.not_to change(CreditLedgerEntry, :count)
    end

    it "requires completed onboarding" do
      token = issue_invitation(organization: organization)

      post "/api/v1/invitations/#{token}/accept",
           headers: auth_headers(firebase_uid: "uid-pending", email: "pending@example.com"),
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("onboarding_required")
      expect(OrganizationMembership.where.not(user: admin)).to be_empty
    end

    it "rejects a token that was already used" do
      token = issue_invitation(organization: organization)
      post "/api/v1/invitations/#{token}/accept", headers: headers_for(invitee), as: :json
      expect(response).to have_http_status(:ok)

      post "/api/v1/invitations/#{token}/accept", headers: headers_for(invitee), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("invalid_invitation")
    end

    it "keeps the existing role when the user already belongs to the organization" do
      create_membership(organization: organization, user: invitee, role: OrganizationMembership::ADMIN)
      token = issue_invitation(organization: organization, role: OrganizationMembership::PARTICIPANT)

      post "/api/v1/invitations/#{token}/accept", headers: headers_for(invitee), as: :json

      expect(response).to have_http_status(:ok)
      expect(invitee.organization_memberships.sole.role).to eq("admin")
    end
  end
end
