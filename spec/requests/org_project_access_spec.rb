# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Organization project access", type: :request do
  def grant_credits!(owner:, amount:, actor:)
    lot = CreditLot.create!(
      owner: owner,
      source: "organization_contract",
      original_amount: amount,
      remaining: amount,
      granted_at: Time.current
    )
    CreditLedgerEntry.create!(
      owner: owner,
      event: "grant",
      amount: amount,
      actor_user: actor,
      reason: lot.source,
      idempotency_key: "topup-#{SecureRandom.hex(4)}",
      credit_lot: lot
    )
  end

  def json_headers(user)
    auth_headers(firebase_uid: user.firebase_uid, email: user.email).merge("CONTENT_TYPE" => "application/json")
  end

  def switch_to!(user, workspace)
    post "/api/v1/workspaces/switch",
         params: { workspace_id: workspace.id }.to_json,
         headers: json_headers(user)
    expect(response).to have_http_status(:ok)
  end

  def org_team!(joining_mode: Project::JOINING_APPLICATION)
    creator = create_onboarded_adult(email: "org-creator-#{SecureRandom.hex(3)}@example.com")
    manager = create_onboarded_adult(email: "org-manager-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "org-participant-#{SecureRandom.hex(3)}@example.com")
    organization = create_organization(name: "Access Org #{SecureRandom.hex(3)}")
    create_membership(organization: organization, user: creator, role: OrganizationMembership::ADMIN)
    create_membership(organization: organization, user: manager, role: OrganizationMembership::MANAGER)
    create_membership(organization: organization, user: participant, role: OrganizationMembership::PARTICIPANT)
    Credits::GrantOrganizationTrial.call(user: creator, organization: organization)
    grant_credits!(owner: organization, amount: 5, actor: creator)
    program = create_program(organization: organization)
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: organization.workspace,
      title: "Org team",
      summary: "Original summary",
      mode: Project::MODE_TEAM,
      joining_mode: joining_mode,
      capacity: 3,
      roles_needed: [ "Designer" ],
      program_id: program.id
    )
    project.update!(
      ends_on: Date.current + 30,
      definition_of_done: "Ship the page",
      proposed_tasks: [
        {
          "title" => "Design",
          "summary" => "Ship",
          "recommended_due_date" => (Date.current + 7).iso8601,
          "submission_expectations" => "PNG"
        }
      ]
    )
    Projects::Confirm.call(project: project, user: creator)

    {
      creator: creator,
      manager: manager,
      participant: participant,
      organization: organization,
      project: project.reload
    }
  end

  it "lets an organization manager open a task they do not belong to without a claim action" do
    ctx = org_team!
    task = ctx[:project].tasks.first
    switch_to!(ctx[:manager], ctx[:organization].workspace)

    get "/api/v1/tasks/#{task.id}", headers: json_headers(ctx[:manager])

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("task", "id")).to eq(task.id)
    expect(response.parsed_body.dig("task", "viewer_can_claim")).to eq(false)

    patch "/api/v1/tasks/#{task.id}/assignment",
          params: { assignee_id: ctx[:manager].id }.to_json,
          headers: json_headers(ctx[:manager])
    expect(response).not_to have_http_status(:ok)
    expect(task.reload.assignee_id).to be_nil
  end

  it "offers Assign to me only to an active participant" do
    ctx = org_team!(joining_mode: Project::JOINING_INSTANT)
    Projects::InstantJoin.call(project: ctx[:project], user: ctx[:participant], participant_role: "Designer")
    task = ctx[:project].tasks.first
    switch_to!(ctx[:participant], ctx[:organization].workspace)

    get "/api/v1/tasks/#{task.id}", headers: json_headers(ctx[:participant])

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("task", "viewer_can_claim")).to eq(true)
  end

  it "hides organization tasks from other organizations" do
    ctx = org_team!
    outsider = create_onboarded_adult(email: "outsider-#{SecureRandom.hex(3)}@example.com")
    other = create_organization(name: "Other Org #{SecureRandom.hex(3)}")
    create_membership(organization: other, user: outsider, role: OrganizationMembership::MANAGER)

    get "/api/v1/tasks/#{ctx[:project].tasks.first.id}", headers: json_headers(outsider)

    expect(response).to have_http_status(:not_found)
  end

  it "lets an organization minor apply and instant-join inside their organization" do
    application_ctx = org_team!
    minor = create_onboarded_adult(email: "minor-#{SecureRandom.hex(3)}@example.com")
    minor.update!(age_status: AgeStatusCalculator::MINOR)
    create_membership(organization: application_ctx[:organization], user: minor, role: OrganizationMembership::PARTICIPANT)

    post "/api/v1/projects/#{application_ctx[:project].id}/applications",
         params: {
           requested_role: "Designer",
           motivation: "I can help this week",
           availability_confirmed: true
         }.to_json,
         headers: json_headers(minor)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig("application", "status")).to eq("pending")

    instant_ctx = org_team!(joining_mode: Project::JOINING_INSTANT)
    joiner = create_onboarded_adult(email: "minor-join-#{SecureRandom.hex(3)}@example.com")
    joiner.update!(age_status: AgeStatusCalculator::UNKNOWN)
    create_membership(organization: instant_ctx[:organization], user: joiner, role: OrganizationMembership::PARTICIPANT)

    post "/api/v1/projects/#{instant_ctx[:project].id}/join",
         params: { participant_role: "Designer" }.to_json,
         headers: json_headers(joiner)

    expect(response).to have_http_status(:created)
  end

  it "still requires an adult account to join a personal project" do
    owner = create_onboarded_adult(email: "personal-owner-#{SecureRandom.hex(3)}@example.com")
    project = Projects::CreateDraft.call(
      user: owner,
      workspace: owner.personal_workspace,
      title: "Personal team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_APPLICATION,
      capacity: 2,
      roles_needed: [ "Designer" ]
    )
    project.update!(ends_on: Date.current + 20)
    Projects::Confirm.call(project: project, user: owner)
    minor = create_onboarded_adult(email: "personal-minor-#{SecureRandom.hex(3)}@example.com")
    minor.update!(age_status: AgeStatusCalculator::MINOR)

    post "/api/v1/projects/#{project.id}/applications",
         params: {
           requested_role: "Designer",
           motivation: "Please let me in",
           availability_confirmed: true
         }.to_json,
         headers: json_headers(minor)

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig("error", "message")).to eq("Verified adult account required to join")
    expect(ProjectApplication.where(project: project, applicant: minor)).to be_empty
  end

  it "lets the creator and organization staff edit an active project" do
    ctx = org_team!
    switch_to!(ctx[:creator], ctx[:organization].workspace)

    patch "/api/v1/projects/#{ctx[:project].id}",
          params: { summary: "Updated summary", joining_mode: Project::JOINING_INSTANT }.to_json,
          headers: json_headers(ctx[:creator])

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "summary")).to eq("Updated summary")
    expect(response.parsed_body.dig("project", "joining_mode")).to eq("instant")
    expect(response.parsed_body.dig("project", "mode")).to eq("team")
    expect(response.parsed_body.dig("project", "program_id")).to eq(ctx[:project].program_id)

    switch_to!(ctx[:manager], ctx[:organization].workspace)
    new_end = (Date.current + 45).iso8601
    patch "/api/v1/projects/#{ctx[:project].id}",
          params: { ends_on: new_end, definition_of_done: "Reviewed by staff" }.to_json,
          headers: json_headers(ctx[:manager])

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "ends_on")).to eq(new_end)
    expect(response.parsed_body.dig("project", "definition_of_done")).to eq("Reviewed by staff")

    2.times do |index|
      member = create_onboarded_adult(email: "seat-#{index}-#{SecureRandom.hex(2)}@example.com")
      create_membership(organization: ctx[:organization], user: member, role: OrganizationMembership::PARTICIPANT)
      ProjectMembership.create!(
        project: ctx[:project],
        user: member,
        role: ProjectMembership::ROLE_PARTICIPANT,
        status: ProjectMembership::STATUS_ACTIVE,
        participant_role: "Designer",
        join_source: ProjectMembership::JOIN_SOURCE_INSTANT
      )
    end

    patch "/api/v1/projects/#{ctx[:project].id}",
          params: { capacity: 1 }.to_json,
          headers: json_headers(ctx[:manager])
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "message")).to include("current participant count")
    expect(ctx[:project].reload.capacity).to eq(3)
  end

  it "keeps active edits off organization participants and personal non-creators" do
    ctx = org_team!
    switch_to!(ctx[:participant], ctx[:organization].workspace)

    patch "/api/v1/projects/#{ctx[:project].id}",
          params: { title: "Taken over" }.to_json,
          headers: json_headers(ctx[:participant])
    expect(response).to have_http_status(:forbidden)

    owner = create_onboarded_adult(email: "solo-owner-#{SecureRandom.hex(3)}@example.com")
    personal = Projects::CreateDraft.call(user: owner, workspace: owner.personal_workspace, title: "Mine")
    personal.update!(ends_on: Date.current + 14)
    Projects::Confirm.call(project: personal, user: owner)
    stranger = create_onboarded_adult(email: "stranger-#{SecureRandom.hex(3)}@example.com")

    patch "/api/v1/projects/#{personal.id}",
          params: { title: "Not mine" }.to_json,
          headers: json_headers(stranger)
    expect(response).to have_http_status(:not_found)
  end
end
