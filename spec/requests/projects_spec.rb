# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Projects API", type: :request do
  let(:user) { create_onboarded_adult(email: "proj@example.com", firebase_uid: "uid-proj") }
  let(:headers) { auth_headers(firebase_uid: user.firebase_uid, email: user.email) }

  it "creates a draft, confirms with credit consume, lists, and cancels with restore" do
    post "/api/v1/projects",
         params: { title: "My solo project", summary: "Build a site", skills: [ "React" ] }.to_json,
         headers: headers.merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:created)
    project_id = response.parsed_body.fetch("project").fetch("id")
    expect(response.parsed_body.dig("project", "status")).to eq("draft")
    expect(Credits::Balance.remaining(owner: user)).to eq(1)

    patch "/api/v1/projects/#{project_id}",
          params: { ends_on: (Date.current + 30).iso8601 }.to_json,
          headers: headers.merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:ok)

    post "/api/v1/projects/#{project_id}/confirm", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "status")).to eq("active")
    expect(response.parsed_body.dig("project", "phase")).to eq("normal")
    expect(response.parsed_body.dig("project", "final_expires_at")).to be_present
    expect(response.parsed_body.dig("session", "credits", "remaining")).to eq(0)
    expect(Credits::Balance.remaining(owner: user)).to eq(0)

    get "/api/v1/projects", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("projects").map { |p| p["id"] }).to include(project_id)

    get "/api/v1/projects/#{project_id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "title")).to eq("My solo project")
    expect(response.parsed_body.dig("project", "phase")).to eq("normal")

    post "/api/v1/projects/#{project_id}/cancel", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "status")).to eq("cancelled")
    expect(response.parsed_body.dig("session", "credits", "remaining")).to eq(1)
  end

  it "rejects confirm without ends_on" do
    post "/api/v1/projects",
         params: { title: "No end date" }.to_json,
         headers: headers.merge("CONTENT_TYPE" => "application/json")
    project_id = response.parsed_body.dig("project", "id")

    post "/api/v1/projects/#{project_id}/confirm", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
    expect(Credits::Balance.remaining(owner: user)).to eq(1)
  end

  it "lets the creator update ends_on on an active project" do
    project = Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Active ends")
    project.update!(ends_on: Date.current + 14)
    Projects::Confirm.call(project: project, user: user)
    new_end = (Date.current + 40).iso8601

    patch "/api/v1/projects/#{project.id}",
          params: { ends_on: new_end }.to_json,
          headers: headers.merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "ends_on")).to eq(new_end)
    expect(response.parsed_body.dig("project", "phase")).to eq("normal")
  end

  it "returns insufficient_credits without activating" do
    Credits::Consume.call(
      owner: user,
      amount: 1,
      reason: "project_create",
      idempotency_key: "spend-all-#{user.id}",
      actor_user: user
    )
    project = Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Blocked")
    project.update!(ends_on: Date.current + 14)

    post "/api/v1/projects/#{project.id}/confirm", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "code")).to eq("insufficient_credits")
    expect(project.reload.status).to eq("draft")
  end

  it "isolates projects by active workspace" do
    org = create_organization(name: "Org Co")
    create_membership(organization: org, user: user, role: OrganizationMembership::ADMIN)
    personal_project = Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Personal draft")

    post "/api/v1/workspaces/switch",
         params: { workspace_id: org.workspace.id }.to_json,
         headers: headers.merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:ok)

    get "/api/v1/projects", headers: headers
    ids = response.parsed_body.fetch("projects").map { |p| p["id"] }
    expect(ids).not_to include(personal_project.id)
  end

  it "opens a public project from Explore for a viewer who is not a member" do
    viewer = create_onboarded_adult(email: "explore-open-#{SecureRandom.hex(3)}@example.com")
    owner = create_onboarded_adult(email: "explore-owner-#{SecureRandom.hex(3)}@example.com")
    solo = Project.create!(
      workspace: owner.personal_workspace,
      creator: owner,
      title: "Public solo",
      mode: "solo",
      status: "active",
      visibility: "public",
      ends_on: Date.current + 30
    )
    finished = Project.create!(
      workspace: owner.personal_workspace,
      creator: owner,
      title: "Finished public",
      mode: "solo",
      status: "completed",
      visibility: "public",
      ends_on: Date.current - 1
    )

    get "/api/v1/projects/#{solo.id}", headers: headers_for(viewer)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "title")).to eq("Public solo")

    get "/api/v1/projects/#{finished.id}", headers: headers_for(viewer)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "status")).to eq("completed")
  end

  it "reports a pending application on a public team project without crashing" do
    viewer = create_onboarded_adult(email: "explore-applicant-#{SecureRandom.hex(3)}@example.com")
    owner = create_onboarded_adult(email: "explore-team-owner-#{SecureRandom.hex(3)}@example.com")
    project = Project.create!(
      workspace: owner.personal_workspace,
      creator: owner,
      title: "Public team",
      mode: "team",
      status: "active",
      visibility: "public",
      joining_mode: "application",
      capacity: 3,
      roles_needed: [ "Designer" ],
      ends_on: Date.current + 30
    )
    ProjectApplication.create!(
      project: project,
      applicant: viewer,
      requested_role: "Designer",
      motivation: "I can help with the visual design.",
      availability_confirmed: true,
      status: "pending"
    )

    get "/api/v1/projects/#{project.id}", headers: headers_for(viewer)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "viewer_application_status")).to eq("pending")
    expect(response.parsed_body.dig("project", "viewer_can_join")).to eq(false)
  end

  it "hides private, draft, and cancelled projects from a viewer who is not a member" do
    viewer = create_onboarded_adult(email: "explore-hidden-#{SecureRandom.hex(3)}@example.com")
    owner = create_onboarded_adult(email: "explore-hidden-owner-#{SecureRandom.hex(3)}@example.com")
    hidden = %w[private draft cancelled].map do |kind|
      Project.create!(
        workspace: owner.personal_workspace,
        creator: owner,
        title: "#{kind} project",
        mode: "solo",
        status: kind == "private" ? "active" : kind,
        visibility: kind == "private" ? "private" : "public",
        ends_on: Date.current + 30
      )
    end

    hidden.each do |project|
      get "/api/v1/projects/#{project.id}", headers: headers_for(viewer)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "discards a draft without changing credits" do
    post "/api/v1/projects",
         params: { title: "Temp" }.to_json,
         headers: headers.merge("CONTENT_TYPE" => "application/json")
    project_id = response.parsed_body.dig("project", "id")

    expect {
      delete "/api/v1/projects/#{project_id}", headers: headers
    }.not_to change { Credits::Balance.remaining(owner: user) }
    expect(response).to have_http_status(:no_content)
  end
end
