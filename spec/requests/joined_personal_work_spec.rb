# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Joined personal work", type: :request do
  def personal_team!(creator:, title:)
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: title,
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ]
    )
    project.update!(
      ends_on: Date.current + 30,
      proposed_tasks: [
        { "title" => "Open task", "summary" => "Claim me", "recommended_due_date" => (Date.current + 4).iso8601 }
      ]
    )
    Projects::Confirm.call(project: project, user: creator)
    project.reload
  end

  it "lists a joined personal team project and lets the member open and claim its task" do
    creator = create_onboarded_adult(email: "joined-creator-#{SecureRandom.hex(3)}@example.com")
    creator.profile.update!(display_name: "Casey Creator")
    joiner = create_onboarded_adult(email: "joined-member-#{SecureRandom.hex(3)}@example.com")
    joiner.profile.update!(display_name: "Jordan Joiner")
    project = personal_team!(creator: creator, title: "Shared personal team")
    Projects::InstantJoin.call(project: project, user: joiner, participant_role: "Designer")
    task = project.tasks.first

    other_creator = create_onboarded_adult(email: "departed-creator-#{SecureRandom.hex(3)}@example.com")
    departed = personal_team!(creator: other_creator, title: "Left behind")
    ProjectMembership.create!(
      project: departed,
      user: joiner,
      role: ProjectMembership::ROLE_PARTICIPANT,
      status: ProjectMembership::STATUS_DEPARTED,
      participant_role: "Designer",
      join_source: ProjectMembership::JOIN_SOURCE_INSTANT
    )

    org = create_organization(name: "Elsewhere #{SecureRandom.hex(2)}")
    org_owner = create_onboarded_adult(email: "org-owner-#{SecureRandom.hex(3)}@example.com")
    create_membership(organization: org, user: org_owner, role: OrganizationMembership::ADMIN)
    program = create_program(organization: org)
    org_project = Project.create!(
      workspace: org.workspace,
      creator: org_owner,
      program: program,
      title: "Other org project",
      mode: Project::MODE_TEAM,
      status: Project::STATUS_ACTIVE,
      visibility: Project::VISIBILITY_PRIVATE,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 2,
      roles_needed: [ "Designer" ],
      ends_on: Date.current + 20
    )
    ProjectMembership.create!(
      project: org_project,
      user: joiner,
      role: ProjectMembership::ROLE_PARTICIPANT,
      status: ProjectMembership::STATUS_ACTIVE,
      participant_role: "Designer",
      join_source: ProjectMembership::JOIN_SOURCE_INSTANT
    )

    get "/api/v1/projects", headers: headers_for(joiner)
    expect(response).to have_http_status(:ok)
    ids = response.parsed_body.fetch("projects").map { |row| row["id"] }
    expect(ids).to include(project.id)
    expect(ids).not_to include(departed.id, org_project.id)

    get "/api/v1/projects/#{project.id}", headers: headers_for(joiner)
    roster = response.parsed_body.dig("project", "memberships")
    joiner_row = roster.find { |row| row["user_id"] == joiner.id }
    expect(joiner_row["display_name"]).to eq("Jordan Joiner")
    expect(joiner_row["profile_slug"]).to eq(joiner.profile.slug)

    stranger = create_onboarded_adult(email: "stranger-#{SecureRandom.hex(3)}@example.com")
    get "/api/v1/tasks/#{task.id}", headers: headers_for(stranger)
    expect(response).to have_http_status(:not_found)

    get "/api/v1/tasks/#{task.id}", headers: headers_for(joiner)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("task", "title")).to eq("Open task")

    patch "/api/v1/tasks/#{task.id}/assignment",
          params: { assignee_id: joiner.id }.to_json,
          headers: headers_for(joiner).merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("task", "assignee_id")).to eq(joiner.id)

    get "/api/v1/tasks", headers: headers_for(joiner)
    expect(response.parsed_body.fetch("tasks").map { |row| row["id"] }).to include(task.id)
  end

  it "shows applicant identity to the creator and omits a slug for a non-public adult" do
    creator = create_onboarded_adult(email: "app-creator-#{SecureRandom.hex(3)}@example.com")
    project = personal_team!(creator: creator, title: "Applications")
    public_applicant = create_onboarded_adult(email: "taylor-#{SecureRandom.hex(3)}@example.com")
    public_applicant.profile.update!(display_name: "Taylor Brooks")
    hidden_applicant = create_onboarded_adult(email: "hidden-#{SecureRandom.hex(3)}@example.com")
    hidden_applicant.profile.update!(display_name: "Private Applicant")
    hidden_applicant.update!(status: User::SUSPENDED)

    pending = ProjectApplication.create!(
      project: project,
      applicant: public_applicant,
      requested_role: "Designer",
      motivation: "I can help with the interface",
      availability_confirmed: true,
      created_at: 2.days.ago
    )
    decided = ProjectApplication.create!(
      project: project,
      applicant: hidden_applicant,
      requested_role: "Researcher",
      motivation: "I already decided",
      availability_confirmed: true,
      status: ProjectApplication::STATUS_APPROVED
    )

    get "/api/v1/projects/#{project.id}", headers: headers_for(creator)
    applications = response.parsed_body.dig("project", "applications")
    expect(applications.map { |row| row["id"] }).to eq([ pending.id, decided.id ])

    public_row = applications.first
    expect(public_row["applicant_display_name"]).to eq("Taylor Brooks")
    expect(public_row["profile_slug"]).to eq(public_applicant.profile.slug)
    expect(public_row["status"]).to eq("pending")
    expect(public_row["requested_role"]).to eq("Designer")
    expect(public_row["created_at"]).to be_present

    hidden_row = applications.second
    expect(hidden_row["applicant_display_name"]).to eq("Private Applicant")
    expect(hidden_row["profile_slug"]).to be_nil
    expect(hidden_row["status"]).to eq("approved")

    get "/api/v1/inbox/items", params: { category: "application" }, headers: headers_for(creator)
    item = response.parsed_body.fetch("items").find { |row| row["related_id"] == pending.id }
    expect(item["title"]).to include("Taylor Brooks")
    expect(item.dig("payload", "applicant_display_name")).to eq("Taylor Brooks")
    expect(item.dig("payload", "profile_slug")).to eq(public_applicant.profile.slug)
  end
end
