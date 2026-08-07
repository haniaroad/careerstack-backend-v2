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

    post "/api/v1/projects/#{project_id}/confirm", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "status")).to eq("active")
    expect(response.parsed_body.dig("session", "credits", "remaining")).to eq(0)
    expect(Credits::Balance.remaining(owner: user)).to eq(0)

    get "/api/v1/projects", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("projects").map { |p| p["id"] }).to include(project_id)

    get "/api/v1/projects/#{project_id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "title")).to eq("My solo project")

    post "/api/v1/projects/#{project_id}/cancel", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("project", "status")).to eq("cancelled")
    expect(response.parsed_body.dig("session", "credits", "remaining")).to eq(1)
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
