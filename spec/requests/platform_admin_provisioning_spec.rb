# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Platform admin provisioning", type: :request do
  def admin_pair
    admin = create_onboarded_adult(email: "prov-admin-#{SecureRandom.hex(3)}@example.com")
    PlatformStaff.create!(user: admin, role: PlatformStaff::ROLE, active: true)
    admin
  end

  it "creates a pending account, sends the sign-in email, and links the first sign-in by email" do
    admin = admin_pair
    organization = create_organization
    email = "pilot-#{SecureRandom.hex(3)}@example.com"

    post "/api/v1/platform_admin/users",
         params: { email: email, organization_id: organization.id, role: "participant", reason: "pilot roster" },
         headers: staff_headers(admin),
         as: :json

    expect(response).to have_http_status(:created)
    user = User.find_by!(email: email)
    expect(user.firebase_uid).to be_nil
    expect(user).to be_pending_onboarding
    expect(user.organization_memberships.active.find_by(organization: organization).role).to eq("participant")
    expect(Notification.find_by!(recipient_user: user, event_key: "account_signin").payload["body"]).to include("Google")
    expect(Notification.where(recipient_user: user, event_key: "welcome")).to be_none

    get "/api/v1/session", headers: auth_headers(firebase_uid: "linked-uid", email: email)
    expect(response).to have_http_status(:ok)
    expect(user.reload.firebase_uid).to eq("linked-uid")
    expect(user.id).to eq(response.parsed_body.dig("user", "id"))
  end

  it "rejects a manager role for a new account and a stale staff session" do
    admin = admin_pair
    organization = create_organization

    post "/api/v1/platform_admin/users",
         params: { email: "lead-#{SecureRandom.hex(3)}@example.com", organization_id: organization.id, role: "manager", reason: "pilot" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(User.where("email LIKE ?", "lead-%")).to be_none

    post "/api/v1/platform_admin/users",
         params: { email: "late-#{SecureRandom.hex(3)}@example.com", reason: "pilot" },
         headers: staff_headers(admin, auth_time: 10.minutes.ago),
         as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "imports a CSV into an organization and reports row results" do
    admin = admin_pair
    organization = create_organization
    existing = create_onboarded_adult(email: "already-#{SecureRandom.hex(3)}@example.com")
    csv = <<~CSV
      email,name,role
      new-#{SecureRandom.hex(3)}@example.com,Ada,participant
      #{existing.email},,participant
      not-an-email,,participant
    CSV

    post "/api/v1/platform_admin/users/import",
         params: { csv: csv, organization_id: organization.id, reason: "cohort upload" },
         headers: staff_headers(admin),
         as: :json

    expect(response).to have_http_status(:ok)
    statuses = response.parsed_body.fetch("rows").map { |row| row["status"] }
    expect(statuses).to eq([ "created", "already_exists", "error" ])
    expect(existing.organization_memberships.active.where(organization: organization)).to exist
  end

  it "creates an organization for an onboarded adult and does not make staff the admin" do
    admin = admin_pair
    founder = create_onboarded_adult(email: "founder-#{SecureRandom.hex(3)}@example.com")

    post "/api/v1/platform_admin/organizations",
         params: {
           admin_user_id: founder.id,
           name: "Accelerate Pilot",
           country: "United States",
           state_region: "MA",
           structure_term_id: structure_term.id,
           primary_goal_term_id: goal_term.id,
           reason: "new customer"
         },
         headers: staff_headers(admin),
         as: :json

    expect(response).to have_http_status(:created)
    organization = Organization.find(response.parsed_body["id"])
    expect(organization.creator_id).to eq(founder.id)
    expect(founder.organization_memberships.admins.find_by(organization: organization)).to be_present
    expect(admin.organization_memberships.where(organization: organization)).to be_none
    expect(Notification.find_by(recipient_user: founder, event_key: "organization_ready")).to be_present
  end

  it "activates a staff project without charging credits, blocks a second participant project, and duplicates without members" do
    admin = admin_pair
    creator = create_onboarded_adult(email: "program-lead-#{SecureRandom.hex(3)}@example.com")
    student = create_onboarded_adult(email: "student-#{SecureRandom.hex(3)}@example.com")
    other = create_onboarded_adult(email: "other-#{SecureRandom.hex(3)}@example.com")
    organization = create_organization
    create_membership(organization: organization, user: creator, role: OrganizationMembership::ADMIN)
    create_membership(organization: organization, user: student)
    create_membership(organization: organization, user: other)
    program = create_program(organization: organization)
    Credits::GrantOrganizationTrial.call(user: creator, organization: organization)
    before = Credits::Balance.remaining(owner: organization)

    payload = {
      creator_id: creator.id,
      program_id: program.id,
      title: "Student studio",
      summary: "A one-person pilot project",
      ends_on: (Date.current + 21).iso8601,
      mode: "team",
      joining_mode: "invite_only",
      capacity: 1,
      roles_needed: [ "UI/UX designer" ],
      skills: [ "UI/UX design" ],
      members: [ { user_id: student.id, participant_role: "UI/UX designer" } ],
      tasks: [ { title: "Draft the brief", acceptance_criteria: "One page", due_on: (Date.current + 7).iso8601, assignee_id: student.id } ],
      reason: "fellowship setup"
    }

    post "/api/v1/platform_admin/organizations/#{organization.id}/projects",
         params: payload,
         headers: staff_headers(admin),
         as: :json

    expect(response).to have_http_status(:created)
    project = Project.find(response.parsed_body.dig("project", "id"))
    expect(project).to be_staff_provisioned
    expect(project.creator_id).to eq(creator.id)
    expect(project.tasks.find_by!(title: "Draft the brief").assignee_id).to eq(student.id)
    expect(Credits::Balance.remaining(owner: organization)).to eq(before)

    post "/api/v1/platform_admin/organizations/#{organization.id}/projects",
         params: payload.merge(title: "Second studio", members: [ { user_id: other.id, participant_role: "UI/UX designer" } ], tasks: [ { title: "Second brief" } ]),
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:created)

    post "/api/v1/platform_admin/projects/#{Project.find_by!(title: "Second studio").id}/members",
         params: { user_id: student.id, participant_role: "UI/UX designer", reason: "try a second project" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "message")).to include("already on an active project")

    post "/api/v1/platform_admin/projects/#{project.id}/duplicate",
         params: { creator_id: creator.id, reason: "copy for the next student" },
         headers: staff_headers(admin),
         as: :json
    expect(response).to have_http_status(:created)
    copy = Project.find(response.parsed_body.dig("project", "id"))
    expect(copy.tasks.map(&:title)).to eq([ "Draft the brief" ])
    expect(copy.tasks.first.assignee_id).to be_nil
    expect(copy.memberships.active.where(role: "participant")).to be_none
    expect(copy.creator_id).to eq(creator.id)
    expect(Credits::Balance.remaining(owner: organization)).to eq(before)
  end
end
