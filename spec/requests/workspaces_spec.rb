# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workspaces", type: :request do
  let(:user) { create_onboarded_adult(email: "member@example.com") }
  let(:organization) { create_organization(name: "Bridge Academy") }

  describe "GET /api/v1/workspaces" do
    it "lists Personal first, then each organization membership" do
      create_membership(organization: organization, user: user)

      get "/api/v1/workspaces", headers: headers_for(user)

      expect(response).to have_http_status(:ok)
      workspaces = response.parsed_body["workspaces"]
      expect(workspaces.map { |workspace| workspace["kind"] }).to eq([ "personal", "organization" ])
      expect(workspaces.last["organization_id"]).to eq(organization.id)
    end

    it "excludes organizations the user does not belong to" do
      create_organization(name: "Unrelated Org")

      get "/api/v1/workspaces", headers: headers_for(user)

      expect(response.parsed_body["workspaces"].map { |workspace| workspace["kind"] }).to eq([ "personal" ])
    end
  end

  describe "GET /api/v1/session" do
    it "defaults the active workspace to Personal when one exists" do
      create_membership(organization: organization, user: user)

      get "/api/v1/session", headers: headers_for(user)

      expect(response.parsed_body.dig("active_workspace", "kind")).to eq("personal")
      expect(response.parsed_body["program_filter"]).to be_nil
      expect(response.parsed_body["can_access_org_admin"]).to be(false)
    end

    it "falls back to an organization workspace when Personal was never granted" do
      minor = create_user(email: "minor@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::MINOR)
      create_membership(organization: organization, user: minor)

      get "/api/v1/session", headers: headers_for(minor)

      expect(response.parsed_body.dig("active_workspace", "kind")).to eq("organization")
    end

    it "ignores a stored active workspace the user no longer belongs to" do
      membership = create_membership(organization: organization, user: user)
      user.update!(active_workspace_id: organization.workspace.id)
      membership.destroy!

      get "/api/v1/session", headers: headers_for(user)

      expect(response.parsed_body.dig("active_workspace", "kind")).to eq("personal")
    end
  end

  describe "POST /api/v1/workspaces/switch" do
    it "activates an organization workspace the user belongs to" do
      create_membership(organization: organization, user: user, role: OrganizationMembership::ADMIN)

      post "/api/v1/workspaces/switch",
           params: { workspace_id: organization.workspace.id },
           headers: headers_for(user),
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("active_workspace", "id")).to eq(organization.workspace.id)
      expect(response.parsed_body["can_access_org_admin"]).to be(true)
      expect(user.reload.active_workspace_id).to eq(organization.workspace.id)
    end

    it "switches back to Personal" do
      create_membership(organization: organization, user: user)
      user.update!(active_workspace_id: organization.workspace.id)

      post "/api/v1/workspaces/switch",
           params: { workspace_id: user.personal_workspace_id },
           headers: headers_for(user),
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("active_workspace", "kind")).to eq("personal")
    end

    it "rejects a workspace the user does not belong to" do
      foreign_workspace = create_organization(name: "Foreign Org").workspace
      original_active = user.active_workspace_id

      post "/api/v1/workspaces/switch",
           params: { workspace_id: foreign_workspace.id },
           headers: headers_for(user),
           as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
      expect(user.reload.active_workspace_id).to eq(original_active)
    end

    it "rejects another user's Personal workspace" do
      other = create_onboarded_adult(email: "other@example.com")

      post "/api/v1/workspaces/switch",
           params: { workspace_id: other.personal_workspace_id },
           headers: headers_for(user),
           as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "returns not_found for an unknown workspace id" do
      post "/api/v1/workspaces/switch",
           params: { workspace_id: SecureRandom.uuid },
           headers: headers_for(user),
           as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig("error", "code")).to eq("not_found")
    end

    it "returns a validation error when workspace_id is missing" do
      post "/api/v1/workspaces/switch", params: {}, headers: headers_for(user), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
    end
  end

  describe "organization program filter context" do
    it "defaults to all programs and lists the available programs" do
      create_membership(organization: organization, user: user)
      create_program(organization: organization, name: "Spring Cohort")
      create_program(organization: organization, name: "Fall Cohort")

      post "/api/v1/workspaces/switch",
           params: { workspace_id: organization.workspace.id },
           headers: headers_for(user),
           as: :json

      program_filter = response.parsed_body["program_filter"]
      expect(program_filter["mode"]).to eq("all")
      expect(program_filter["program_id"]).to be_nil
      expect(program_filter["available_programs"].map { |program| program["name"] }).to eq([ "Fall Cohort", "Spring Cohort" ])
    end

    it "reports a stored program preference for that organization" do
      program = create_program(organization: organization, name: "Spring Cohort")
      membership = create_membership(organization: organization, user: user)
      membership.update!(program_filter_program: program)
      user.update!(active_workspace_id: organization.workspace.id)

      get "/api/v1/session", headers: headers_for(user)

      expect(response.parsed_body["program_filter"]).to include(
        "mode" => "program",
        "program_id" => program.id
      )
    end
  end
end
