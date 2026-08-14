# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public surfaces API", type: :request do
  include IdentityFixtures
  include AuthHelpers

  let(:user) { create_onboarded_adult(email: "creator@example.com") }

  def confirm_public_project!(title: "Public Portfolio", visibility: Project::VISIBILITY_PUBLIC)
    project = Projects::CreateDraft.call(
      user: user,
      workspace: user.personal_workspace,
      title: title,
      visibility: visibility,
      summary: "Build in public"
    )
    project.update!(
      ends_on: Date.current + 21.days,
      definition_of_done: "Ship a portfolio site"
    )
    Projects::Confirm.call(project: project, user: user)
    project.reload
  end

  describe "GET /api/v1/public/projects/:slug" do
    it "returns a redacted public project without auth" do
      project = confirm_public_project!
      Task.create!(
        project: project,
        title: "Wireframe",
        acceptance_criteria: "Three screens",
        position: 0
      )

      get "/api/v1/public/projects/#{project.slug}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body.fetch("project")
      expect(body["slug"]).to eq(project.slug)
      expect(body["title"]).to eq("Public Portfolio")
      expect(body["tasks"].first).to include("title" => "Wireframe", "acceptance_criteria" => "Three screens")
      expect(body["creator"]).to include("display_name" => user.profile.display_name, "profile_slug" => user.profile.slug)
      expect(body).not_to have_key("memberships")
      expect(body).not_to have_key("workspace_id")
      expect(body).not_to have_key("creator_id")
    end

    it "returns not_found for private projects" do
      project = confirm_public_project!(title: "Private Work", visibility: Project::VISIBILITY_PRIVATE)

      get "/api/v1/public/projects/#{project.slug}"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig("error", "code")).to eq("not_found")
    end

    it "returns not_found for draft projects" do
      project = Projects::CreateDraft.call(
        user: user,
        workspace: user.personal_workspace,
        title: "Still Drafting",
        visibility: Project::VISIBILITY_PUBLIC
      )

      get "/api/v1/public/projects/#{project.slug}"

      expect(response).to have_http_status(:not_found)
    end

    it "returns not_found for cancelled projects" do
      project = confirm_public_project!(title: "Cancelled Public")
      Projects::Cancel.call(project: project, user: user)

      get "/api/v1/public/projects/#{project.slug}"

      expect(response).to have_http_status(:not_found)
    end

    it "returns not_found for missing slugs" do
      get "/api/v1/public/projects/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/public/profiles/:slug" do
    it "returns an eligible public adult profile without auth" do
      get "/api/v1/public/profiles/#{user.profile.slug}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig("profile", "details", "slug")).to eq(user.profile.slug)
      expect(body["canonical_path"]).to eq("/profile/#{user.profile.slug}")
      expect(body["indexable"]).to eq(true)
      expect(body.dig("profile", "details")).not_to have_key("date_of_birth")
    end

    it "returns not_found for age-up pending profiles" do
      other = create_onboarded_adult(email: "pending-public@example.com")
      other.update!(onboarding_path: "organization_invited")
      other.age_visibility_preference.require_visibility_review!

      get "/api/v1/public/profiles/#{other.profile.slug}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "project slug and visibility" do
    it "assigns a stable slug and personal default visibility on create" do
      project = Projects::CreateDraft.call(
        user: user,
        workspace: user.personal_workspace,
        title: "Stable Slug Project"
      )

      expect(project.slug).to be_present
      expect(project.visibility).to eq(Project::VISIBILITY_PUBLIC)

      original = project.slug
      Projects::UpdateDraft.call(project: project, user: user, title: "Renamed Title")
      expect(project.reload.slug).to eq(original)
    end

    it "defaults organization projects to private" do
      org = create_organization(name: "Org Co")
      create_membership(organization: org, user: user, role: OrganizationMembership::ADMIN)
      workspace = org.workspace
      program = create_program(organization: org)

      project = Projects::CreateDraft.call(
        user: user,
        workspace: workspace,
        title: "Org Draft",
        program_id: program.id
      )

      expect(project.visibility).to eq(Project::VISIBILITY_PRIVATE)
    end

    it "allows the creator to update visibility on an active project" do
      project = confirm_public_project!

      patch "/api/v1/projects/#{project.id}",
            params: { visibility: Project::VISIBILITY_PRIVATE },
            headers: headers_for(user),
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("project", "visibility")).to eq("private")
      expect(project.reload.visibility).to eq(Project::VISIBILITY_PRIVATE)
    end

    it "rejects slug changes" do
      project = Projects::CreateDraft.call(
        user: user,
        workspace: user.personal_workspace,
        title: "Immutable Slug"
      )

      expect {
        project.update!(slug: "hacker-changed")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
