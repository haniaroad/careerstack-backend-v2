# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Organization administration", type: :request do
  let(:admin) { create_onboarded_adult(email: "org-admin@example.com") }
  let(:manager) { create_onboarded_adult(email: "org-manager@example.com") }
  let(:participant) { create_onboarded_adult(email: "org-participant@example.com") }
  let(:organization) { create_organization(name: "Bridge Academy") }

  before do
    create_membership(organization: organization, user: admin, role: OrganizationMembership::ADMIN)
    create_membership(organization: organization, user: manager, role: OrganizationMembership::MANAGER)
    create_membership(organization: organization, user: participant)
  end

  def switch_to!(user, workspace)
    post "/api/v1/workspaces/switch",
         params: { workspace_id: workspace.id },
         headers: headers_for(user),
         as: :json
  end

  def org_headers(user)
    switch_to!(user, organization.workspace)
    headers_for(user)
  end

  describe "programs" do
    it "lets staff create a draft without consuming credits" do
      headers = org_headers(manager)

      expect {
        post "/api/v1/organizations/#{organization.id}/programs",
             params: { name: "Fall Cohort", description: "New cohort" },
             headers: headers,
             as: :json
      }.not_to change(CreditLedgerEntry, :count)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("program", "status")).to eq("draft")
    end

    it "lets staff activate a draft" do
      program = create_program(organization: organization, name: "Drafty", status: Program::STATUS_DRAFT)
      headers = org_headers(manager)

      patch "/api/v1/programs/#{program.id}",
            params: { status: "active" },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(program.reload.status).to eq("active")
    end

    it "lets an administrator delete an empty draft and forbids a manager" do
      program = create_program(organization: organization, name: "Empty", status: Program::STATUS_DRAFT)

      delete "/api/v1/programs/#{program.id}", headers: org_headers(manager)
      expect(response).to have_http_status(:forbidden)
      expect(Program.exists?(program.id)).to be(true)

      delete "/api/v1/programs/#{program.id}", headers: org_headers(admin)
      expect(response).to have_http_status(:no_content)
      expect(Program.exists?(program.id)).to be(false)
    end

    it "rejects deleting a draft that has invitations" do
      program = create_program(organization: organization, name: "Busy", status: Program::STATUS_DRAFT)
      Invitation.issue!(organization: organization, program: program)

      delete "/api/v1/programs/#{program.id}", headers: org_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Program.exists?(program.id)).to be(true)
    end

    it "lets an administrator archive and blocks new projects and invitations" do
      program = create_program(organization: organization, name: "Archive me")
      headers = org_headers(admin)

      post "/api/v1/programs/#{program.id}/archive", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(program.reload).to be_archived

      post "/api/v1/projects",
           params: { title: "Blocked", program_id: program.id },
           headers: headers,
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post "/api/v1/invitations",
           params: { organization_id: organization.id, program_id: program.id },
           headers: headers,
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "forbids a manager from archiving" do
      program = create_program(organization: organization)

      post "/api/v1/programs/#{program.id}/archive", headers: org_headers(manager), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(program.reload).to be_active
    end

    it "forbids a participant from listing programs" do
      get "/api/v1/organizations/#{organization.id}/programs", headers: org_headers(participant)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "project program association and filter" do
    it "requires a program for organization drafts and scopes the list" do
      program_a = create_program(organization: organization, name: "A")
      program_b = create_program(organization: organization, name: "B")
      headers = org_headers(admin)

      post "/api/v1/projects", params: { title: "No program" }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post "/api/v1/projects",
           params: { title: "In A", program_id: program_a.id },
           headers: headers,
           as: :json
      expect(response).to have_http_status(:created)
      id_a = response.parsed_body.dig("project", "id")

      post "/api/v1/projects",
           params: { title: "In B", program_id: program_b.id },
           headers: headers,
           as: :json
      id_b = response.parsed_body.dig("project", "id")

      post "/api/v1/workspaces/program_filter",
           params: { mode: "program", program_id: program_a.id },
           headers: headers,
           as: :json
      expect(response.parsed_body.dig("program_filter", "program_id")).to eq(program_a.id)

      get "/api/v1/projects", headers: headers
      ids = response.parsed_body["projects"].map { |row| row["id"] }
      expect(ids).to include(id_a)
      expect(ids).not_to include(id_b)
    end
  end

  describe "members" do
    it "lists members with age_status and never DOB" do
      get "/api/v1/organizations/#{organization.id}/memberships", headers: org_headers(admin)

      expect(response).to have_http_status(:ok)
      row = response.parsed_body["memberships"].find { |item| item["user_id"] == participant.id }
      expect(row["age_status"]).to eq("adult")
      expect(row.keys).not_to include("date_of_birth")
      expect(JSON.generate(response.parsed_body)).not_to match(/date_of_birth/)
    end

    it "searches by email" do
      get "/api/v1/organizations/#{organization.id}/memberships",
          params: { q: "org-participant" },
          headers: org_headers(admin)

      ids = response.parsed_body["memberships"].map { |row| row["user_id"] }
      expect(ids).to contain_exactly(participant.id)
    end

    it "lets an administrator change programs and forbids a manager from promoting" do
      program = create_program(organization: organization, name: "Cohort")
      membership = participant.membership_for(organization)

      patch "/api/v1/organization_memberships/#{membership.id}",
            params: { program_ids: [ program.id ] },
            headers: org_headers(admin),
            as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("membership", "program_ids")).to eq([ program.id ])

      patch "/api/v1/organization_memberships/#{membership.id}",
            params: { role: "admin" },
            headers: org_headers(manager),
            as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "lets an administrator remove a participant and blocks last-admin removal" do
      membership = participant.membership_for(organization)

      post "/api/v1/organization_memberships/#{membership.id}/remove",
           params: { reason: "left_program" },
           headers: org_headers(manager),
           as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/organization_memberships/#{membership.id}/remove",
           params: { reason: "left_program" },
           headers: org_headers(admin),
           as: :json
      expect(response).to have_http_status(:ok)
      expect(membership.reload).to be_removed
      expect(participant.reload.usable_workspaces.map(&:organization_id)).not_to include(organization.id)

      admin_membership = admin.membership_for(organization)
      post "/api/v1/organization_memberships/#{admin_membership.id}/remove",
           params: { reason: "other" },
           headers: org_headers(admin),
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("last_administrator")
    end

    it "rejects cross-org membership mutation" do
      other = create_organization(name: "Other Org")
      outsider = create_onboarded_adult(email: "outsider@example.com")
      other_membership = create_membership(organization: other, user: outsider)

      patch "/api/v1/organization_memberships/#{other_membership.id}",
            params: { role: "participant" },
            headers: org_headers(admin),
            as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "invitations list and accept enrollment" do
    it "lists invitations for staff" do
      Invitation.issue!(organization: organization, email: "new@example.com", created_by_user: admin)

      get "/api/v1/organizations/#{organization.id}/invitations", headers: org_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["invitations"].first["email"]).to eq("new@example.com")
    end

    it "creates a program enrollment on accept" do
      program = create_program(organization: organization)
      token = issue_invitation(organization: organization, program: program)
      invitee = create_onboarded_adult(email: "joined@example.com")

      post "/api/v1/invitations/#{token}/accept", headers: headers_for(invitee), as: :json

      expect(response).to have_http_status(:ok)
      membership = invitee.organization_memberships.sole
      expect(membership.enrolled_programs).to contain_exactly(program)
    end
  end

  describe "credits, upgrade request, and offboarding" do
    it "lets managers read balance but not history" do
      get "/api/v1/credits", headers: org_headers(manager)
      expect(response).to have_http_status(:ok)

      get "/api/v1/credits/history", headers: org_headers(manager)
      expect(response).to have_http_status(:forbidden)

      get "/api/v1/credits/history", headers: org_headers(admin)
      expect(response).to have_http_status(:ok)
    end

    it "upserts a single open upgrade request for administrators" do
      headers = org_headers(admin)
      payload = {
        expected_participants: "40",
        expected_projects_or_cohorts: "2 cohorts",
        timeline: "Fall 2026",
        notes: "Need more seats"
      }

      put "/api/v1/organizations/#{organization.id}/upgrade_request", params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      first_id = response.parsed_body.dig("upgrade_request", "id")

      put "/api/v1/organizations/#{organization.id}/upgrade_request",
          params: payload.merge(expected_participants: "80"),
          headers: headers,
          as: :json
      expect(response.parsed_body.dig("upgrade_request", "id")).to eq(first_id)
      expect(response.parsed_body.dig("upgrade_request", "expected_participants")).to eq("80")
      expect(OrganizationUpgradeRequest.where(organization: organization).count).to eq(1)

      put "/api/v1/organizations/#{organization.id}/upgrade_request", params: payload, headers: org_headers(manager), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "blocks writes during offboarding and disables after the window" do
      Organizations::StartOffboarding.call(organization: organization)
      organization.update_columns(offboarding_ends_on: Date.yesterday)

      post "/api/v1/organizations/#{organization.id}/programs",
           params: { name: "Blocked" },
           headers: org_headers(admin),
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "code")).to eq("organization_read_only")

      OrganizationOffboardingSweepJob.perform_now
      expect(organization.reload).to be_workspace_disabled

      get "/api/v1/workspaces", headers: headers_for(admin)
      kinds = response.parsed_body["workspaces"].map { |row| row["kind"] }
      expect(kinds).to eq([ "personal" ])
    end

    it "returns an operational pulse for staff and forbids participants" do
      create_program(organization: organization, name: "Live")

      get "/api/v1/organizations/#{organization.id}/admin", headers: org_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("operational_pulse", "active_programs")).to eq(1)
      expect(response.parsed_body.dig("organization", "workspace_status")).to eq("active")

      get "/api/v1/organizations/#{organization.id}/admin", headers: org_headers(participant)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
