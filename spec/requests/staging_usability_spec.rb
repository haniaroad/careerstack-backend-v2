# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Staging usability", type: :request do
  describe "home warning dismissals" do
    let(:user) { create_onboarded_adult(email: "home-user@example.com") }
    let(:other) { create_onboarded_adult(email: "home-other@example.com") }

    def ending_project_for(owner)
      project = Projects::CreateDraft.call(
        user: owner,
        workspace: owner.personal_workspace,
        title: "Ending project"
      )
      project.update_columns(status: Project::STATUS_ACTIVE, ends_on: Date.current + 3)
      project.reload
    end

    it "stores a dismissal and hides only that phase" do
      project = ending_project_for(user)
      expect(project.home_warning_phase).to eq("ending_soon")

      post "/api/v1/home/warning_dismissals",
           params: { project_id: project.id, phase: "ending_soon" },
           headers: headers_for(user),
           as: :json

      expect(response).to have_http_status(:created)

      get "/api/v1/home/warning_dismissals", headers: headers_for(user)
      expect(response.parsed_body["dismissals"]).to include(
        "project_id" => project.id, "phase" => "ending_soon"
      )

      project.update_columns(ends_on: Date.current - 1)
      expect(project.reload.home_warning_phase).to eq("grace_period")

      post "/api/v1/home/warning_dismissals",
           params: { project_id: project.id, phase: "ending_soon" },
           headers: headers_for(user),
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post "/api/v1/home/warning_dismissals",
           params: { project_id: project.id, phase: "ending_soon" },
           headers: headers_for(other),
           as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "project invitation by email" do
    let(:creator) { create_onboarded_adult(email: "invite-creator@example.com") }
    let(:invitee) { create_onboarded_adult(email: "Teammate@Example.com") }

    def invite_only_project
      project = Projects::CreateDraft.call(
        user: creator,
        workspace: creator.personal_workspace,
        title: "Invite team",
        mode: Project::MODE_TEAM,
        joining_mode: Project::JOINING_INVITE_ONLY,
        capacity: 3,
        roles_needed: [ "Designer" ]
      )
      project.update!(ends_on: Date.current + 30)
      Projects::Confirm.call(project: project, user: creator)
      project.reload
    end

    it "invites an existing user by email and refuses an unknown address or the creator" do
      invitee
      project = invite_only_project

      post "/api/v1/projects/#{project.id}/invitations",
           params: { invitee_email: "teammate@example.com", requested_role: "Designer" },
           headers: headers_for(creator),
           as: :json

      expect(response).to have_http_status(:created), response.body
      body = response.parsed_body["invitation"]
      expect(body["invitee_id"]).to eq(invitee.id)
      expect(body["invitee_email"]).to eq(invitee.email)

      get "/api/v1/projects/#{project.id}", headers: headers_for(creator)
      pending = response.parsed_body.dig("project", "pending_invitations")
      expect(pending.map { |row| row["invitee_email"] }).to include(invitee.email)

      post "/api/v1/projects/#{project.id}/invitations",
           params: { invitee_email: "missing@example.com", requested_role: "Designer" },
           headers: headers_for(creator),
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to include("CareerStack account")

      post "/api/v1/projects/#{project.id}/invitations",
           params: { invitee_email: creator.email, requested_role: "Designer" },
           headers: headers_for(creator),
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("error", "message")).to include("yourself")
    end
  end

  describe "profile activity and visibility" do
    let(:user) { create_onboarded_adult(email: "activity-owner@example.com") }

    it "counts a submission in the current UTC week" do
      project = Projects::CreateDraft.call(
        user: user,
        workspace: user.personal_workspace,
        title: "Activity project"
      )
      ContributionEvent.create!(
        user: user,
        kind: ContributionEvent::KIND_TASK_SUBMITTED,
        occurred_at: Time.current,
        subject_type: "Project",
        subject_id: project.id,
        workspace_kind: ContributionEvent::WORKSPACE_PERSONAL,
        private_org: false,
        idempotency_key: "task_submitted:spec:#{project.id}"
      )

      get "/api/v1/profiles/me", headers: headers_for(user)
      activity = response.parsed_body.dig("profile", "stats", "activity")
      current = Time.current.utc.to_date.beginning_of_week(:monday).iso8601
      week = activity.find { |point| point["week_start"] == current }
      expect(week["count"]).to eq(1)
    end

    it "lets an independent adult make the profile private and public again" do
      viewer = create_onboarded_adult(email: "activity-viewer@example.com")
      slug = user.profile.slug

      post "/api/v1/profiles/me/visibility",
           params: { decision: "reverse" },
           headers: headers_for(user),
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("profile", "public_identity_visible")).to eq(false)
      expect(user.reload.public_identity_visible?).to eq(false)

      get "/api/v1/profiles/#{slug}", headers: headers_for(viewer)
      expect(response).to have_http_status(:not_found)

      post "/api/v1/profiles/me/visibility",
           params: { decision: "confirm" },
           headers: headers_for(user),
           as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.public_identity_visible?).to eq(true)
      get "/api/v1/profiles/#{slug}", headers: headers_for(viewer)
      expect(response).to have_http_status(:ok)
    end
  end
end
