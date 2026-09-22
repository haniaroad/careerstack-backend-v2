# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Peer reviews", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def grant_credits!(owner:, amount:, actor:)
    source = owner.is_a?(Organization) ? "organization_contract" : "personal_pack_purchase"
    lot = CreditLot.create!(
      owner: owner,
      source: source,
      original_amount: amount,
      remaining: amount,
      stripe_payment_ref: owner.is_a?(Organization) ? nil : "pi_test_#{SecureRandom.hex(4)}",
      granted_at: Time.current
    )
    CreditLedgerEntry.create!(
      owner: owner,
      event: "grant",
      amount: amount,
      actor_user: actor,
      reason: source,
      idempotency_key: "topup-#{SecureRandom.hex(4)}",
      credit_lot: lot
    )
  end

  def completed_org_team!
    creator = create_onboarded_adult(email: "pr-req-c-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "pr-req-p-#{SecureRandom.hex(3)}@example.com")
    outsider = create_onboarded_adult(email: "pr-req-o-#{SecureRandom.hex(3)}@example.com")
    organization = create_organization(name: "PR Org #{SecureRandom.hex(3)}")
    create_membership(organization: organization, user: creator, role: OrganizationMembership::ADMIN)
    create_membership(organization: organization, user: participant, role: OrganizationMembership::PARTICIPANT)
    Credits::GrantOrganizationTrial.call(user: creator, organization: organization)
    grant_credits!(owner: organization, amount: 5, actor: creator)
    program = create_program(organization: organization)
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: organization.workspace,
      title: "Request team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ],
      program_id: program.id
    )
    project.update!(
      ends_on: Date.current + 30,
      skills: [ "Facilitation" ],
      proposed_tasks: [ { "title" => "One", "summary" => "x", "recommended_due_date" => (Date.current + 5).iso8601, "submission_expectations" => "Text" } ]
    )
    Projects::Confirm.call(project: project, user: creator)
    ProjectMembership.create!(
      project: project.reload,
      user: participant,
      role: ProjectMembership::ROLE_PARTICIPANT,
      status: ProjectMembership::STATUS_ACTIVE,
      participant_role: "Designer",
      join_source: ProjectMembership::JOIN_SOURCE_INSTANT
    )
    project.tasks.find_each { |task| task.update!(assignee_id: participant.id, status: Task::STATUS_APPROVED) }
    Projects::Lifecycle::Evaluate.call(project: project.reload)
    {
      creator: creator,
      participant: participant,
      outsider: outsider,
      organization: organization,
      project: project.reload
    }
  end

  def switch_to!(user, workspace)
    post "/api/v1/workspaces/switch", params: { workspace_id: workspace.id }, headers: headers_for(user), as: :json
    expect(response).to have_http_status(:ok)
  end

  it "lists the actor's slots in the active workspace and rejects unauthenticated access" do
    ctx = completed_org_team!
    switch_to!(ctx[:participant], ctx[:organization].workspace)

    get "/api/v1/peer_reviews", headers: headers_for(ctx[:participant])
    expect(response).to have_http_status(:ok)
    participant_rows = response.parsed_body.fetch("peer_reviews")
    expect(participant_rows.map { |row| row.fetch("to_user_id") }).to contain_exactly(ctx[:creator].id)
    expect(participant_rows.map { |row| row.fetch("from_user_id") }).to contain_exactly(ctx[:participant].id)

    switch_to!(ctx[:creator], ctx[:organization].workspace)
    get "/api/v1/peer_reviews", headers: headers_for(ctx[:creator])
    creator_rows = response.parsed_body.fetch("peer_reviews")
    expect(creator_rows.map { |row| row.fetch("to_user_id") }).to contain_exactly(ctx[:participant].id)
    expect(creator_rows.map { |row| row.fetch("id") }).not_to include(*participant_rows.map { |row| row.fetch("id") })

    switch_to!(ctx[:participant], ctx[:participant].personal_workspace)
    get "/api/v1/peer_reviews", headers: headers_for(ctx[:participant])
    expect(response.parsed_body.fetch("peer_reviews")).to eq([])

    get "/api/v1/peer_reviews"
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects submit by a non-reviewer and when the project is not completed" do
    ctx = completed_org_team!
    slot = PeerReview.find_by!(project: ctx[:project], reviewer: ctx[:participant], reviewee: ctx[:creator])

    post "/api/v1/peer_reviews/#{slot.id}/submit",
         params: { rating: 4, comment: "Stolen" },
         headers: headers_for(ctx[:outsider]),
         as: :json
    expect(response).to have_http_status(:forbidden)

    active = Projects::CreateDraft.call(
      user: ctx[:creator],
      workspace: ctx[:organization].workspace,
      title: "Still active",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 2,
      roles_needed: [ "Designer" ],
      program_id: ctx[:project].program_id
    )
    active.update!(status: Project::STATUS_ACTIVE, ends_on: Date.current + 14)
    stolen = PeerReview.create!(
      project: active,
      reviewer: ctx[:participant],
      reviewee: ctx[:creator],
      status: PeerReview::STATUS_AVAILABLE
    )
    post "/api/v1/peer_reviews/#{stolen.id}/submit",
         params: { rating: 4, comment: "Too soon" },
         headers: headers_for(ctx[:participant]),
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "includes anonymized received reviews on public profiles and 404s restricted identity" do
    ctx = completed_org_team!
    slot = PeerReview.find_by!(project: ctx[:project], reviewer: ctx[:participant], reviewee: ctx[:creator])
    PeerReviews::Submit.call(review: slot, actor: ctx[:participant], rating: 5, comment: "Named praise")
    ctx[:participant].update!(age_status: AgeStatusCalculator::MINOR)

    get "/api/v1/public/profiles/#{ctx[:creator].profile.slug}"
    expect(response).to have_http_status(:ok)
    cards = response.parsed_body.dig("profile", "peer_reviews")
    expect(cards.length).to eq(1)
    expect(cards.first.fetch("reviewer_display_name")).to eq("Verified project teammate")
    expect(cards.first).not_to have_key("rating")
    expect(cards.first.fetch("body")).to eq("Named praise")

    ctx[:creator].update!(age_status: AgeStatusCalculator::MINOR, onboarding_path: "organization_invited")
    get "/api/v1/public/profiles/#{ctx[:creator].profile.slug}"
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.to_s).not_to include("Named praise")
  end

  it "lets a reader report a review and rejects the author and anonymous clients" do
    ctx = completed_org_team!
    slot = PeerReview.find_by!(project: ctx[:project], reviewer: ctx[:participant], reviewee: ctx[:creator])
    PeerReviews::Submit.call(review: slot, actor: ctx[:participant], rating: 4, comment: "Reportable")

    post "/api/v1/peer_reviews/#{slot.id}/reports",
         params: { report_type: "inappropriate", reason_category: "other" },
         headers: headers_for(ctx[:creator]),
         as: :json
    expect(response).to have_http_status(:created)

    post "/api/v1/peer_reviews/#{slot.id}/reports",
         params: { report_type: "harassment", reason_category: "harassment" },
         headers: headers_for(ctx[:participant]),
         as: :json
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/peer_reviews/#{slot.id}/reports",
         params: { report_type: "inappropriate", reason_category: "other" },
         as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "emits one request reminder per recipient per project" do
    ctx = completed_org_team!
    expect(Notification.where(event_key: "peer_review_request", recipient_user: ctx[:participant]).count).to eq(1)

    travel 4.days do
      PeerReviews::Reminder.call
      PeerReviews::Reminder.call
    end
    expect(Notification.where(event_key: "peer_review_request", recipient_user: ctx[:participant]).count).to eq(2)
  end

  it "backfills historical completed teams without emitting" do
    creator = create_onboarded_adult(email: "pr-req-bf-c-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "pr-req-bf-p-#{SecureRandom.hex(3)}@example.com")
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Historical team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 2,
      roles_needed: [ "Designer" ]
    )
    project.update!(status: Project::STATUS_COMPLETED, completed_at: 1.day.ago, ends_on: Date.current + 14)
    ProjectMembership.create!(project: project, user: creator, role: ProjectMembership::ROLE_CREATOR, status: ProjectMembership::STATUS_ACTIVE)
    ProjectMembership.create!(
      project: project,
      user: participant,
      role: ProjectMembership::ROLE_PARTICIPANT,
      status: ProjectMembership::STATUS_ACTIVE,
      participant_role: "Designer",
      join_source: ProjectMembership::JOIN_SOURCE_INSTANT
    )

    expect {
      PeerReviews::Backfill.call
    }.not_to change { Notification.where(event_key: "peer_review_request").count }
    expect(PeerReview.where(project: project).count).to eq(2)
  end
end
