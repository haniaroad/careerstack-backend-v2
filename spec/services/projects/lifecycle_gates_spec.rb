# frozen_string_literal: true

require "rails_helper"

RSpec.describe Projects::Lifecycle::ActionGate do
  def grant_credits!(owner:, amount:, actor:)
    lot = CreditLot.create!(
      owner: owner,
      source: owner.is_a?(Organization) ? "organization_contract" : "personal_pack_purchase",
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
      reason: lot.source,
      idempotency_key: "topup-#{SecureRandom.hex(4)}",
      credit_lot: lot
    )
  end

  def team_project!(ends_on: Date.current + 20)
    creator = create_onboarded_adult(email: "gate-c-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "gate-p-#{SecureRandom.hex(3)}@example.com")
    organization = create_organization(name: "Gate Org #{SecureRandom.hex(3)}")
    create_membership(organization: organization, user: creator, role: OrganizationMembership::ADMIN)
    create_membership(organization: organization, user: participant, role: OrganizationMembership::PARTICIPANT)
    Credits::GrantOrganizationTrial.call(user: creator, organization: organization)
    grant_credits!(owner: organization, amount: 5, actor: creator)

    project = Projects::CreateDraft.call(
      user: creator,
      workspace: organization.workspace,
      title: "Gate team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ]
    )
    project.update!(
      ends_on: ends_on,
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
    Projects::InstantJoin.call(project: project.reload, user: participant, participant_role: "Designer")
    task = project.reload.tasks.first
    Tasks::Assign.call(task: task, actor: creator, assignee: participant)

    {
      creator: creator,
      participant: participant,
      project: project.reload,
      task: task.reload,
      joiner: create_onboarded_adult(email: "gate-j-#{SecureRandom.hex(3)}@example.com").tap { |u|
        create_membership(organization: organization, user: u, role: OrganizationMembership::PARTICIPANT)
      }
    }
  end

  it "blocks join in grace and allows submit" do
    ctx = team_project!
    ctx[:project].update_columns(ends_on: Date.current - 1)

    expect {
      described_class.assert!(project: ctx[:project].reload, action: :join)
    }.to raise_error(DomainError) { |e| expect(e.code).to eq("lifecycle_action_denied") }

    expect {
      Projects::InstantJoin.call(project: ctx[:project].reload, user: ctx[:joiner], participant_role: "Designer")
    }.to raise_error(DomainError)

    Tasks::Submit.call(task: ctx[:task], user: ctx[:participant], body: "Work", links: [], signed_blob_ids: [], enqueue_review: false)
    expect(ctx[:task].reload.status).to eq(Task::STATUS_SUBMITTED)
  end

  it "allows leave in grace" do
    ctx = team_project!
    ctx[:project].update_columns(ends_on: Date.current - 1)

    membership = Projects::Leave.call(
      project: ctx[:project].reload,
      user: ctx[:participant],
      reason_category: ProjectMembershipEvent::REASON_CATEGORIES.first
    )
    expect(membership.status).to eq(ProjectMembership::STATUS_DEPARTED)
  end

  it "blocks submit after expiration" do
    ctx = team_project!
    ctx[:project].update_columns(ends_on: Date.current - 8)
    Projects::Lifecycle::Evaluate.call(project: ctx[:project].reload)

    expect {
      Tasks::Submit.call(task: ctx[:task].reload, user: ctx[:participant], body: "Late", links: [], signed_blob_ids: [])
    }.to raise_error(DomainError)
  end

  it "blocks corrections within 48h of final_expires_at" do
    ctx = team_project!(ends_on: Date.current + 20)
    Tasks::Submit.call(task: ctx[:task], user: ctx[:participant], body: "Work", links: [], signed_blob_ids: [], enqueue_review: false)
    # final_expires_at = ends_on + 7 EOD; set ends_on so final is tomorrow EOD (< 48h remaining)
    ctx[:project].update_columns(ends_on: Date.current - 6)

    expect {
      Tasks::CreatorReview.call(
        task: ctx[:task].reload,
        actor: ctx[:creator],
        decision: "corrections_requested",
        feedback: "Too close"
      )
    }.to raise_error(DomainError) { |e| expect(e.code).to eq("corrections_window_closed") }
  end

  it "allows corrections when more than 48h remain before final expiration" do
    ctx = team_project!(ends_on: Date.current + 20)
    Tasks::Submit.call(task: ctx[:task], user: ctx[:participant], body: "Work", links: [], signed_blob_ids: [], enqueue_review: false)
    ctx[:project].update_columns(ends_on: Date.current - 1)

    updated = Tasks::CreatorReview.call(
      task: ctx[:task].reload,
      actor: ctx[:creator],
      decision: "corrections_requested",
      feedback: "Revise please"
    )
    expect(updated.status).to eq(Task::STATUS_CORRECTIONS_REQUESTED)
  end
end
