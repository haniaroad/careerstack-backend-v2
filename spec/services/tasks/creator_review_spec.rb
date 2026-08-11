# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::CreatorReview do
  def grant_credits!(owner:, amount:, actor:)
    source = owner.is_a?(Organization) ? "organization_contract" : "personal_pack_purchase"
    ref = owner.is_a?(Organization) ? nil : "pi_test_#{SecureRandom.hex(4)}"
    lot = CreditLot.create!(
      owner: owner,
      source: source,
      original_amount: amount,
      remaining: amount,
      stripe_payment_ref: ref,
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

  def team_with_submitted_task(ends_on: Date.current + 30)
    creator = create_onboarded_adult(email: "creator-review-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "assignee-#{SecureRandom.hex(3)}@example.com")
    organization = create_organization(name: "Review Org #{SecureRandom.hex(3)}")
    create_membership(organization: organization, user: creator, role: OrganizationMembership::ADMIN)
    create_membership(organization: organization, user: participant, role: OrganizationMembership::PARTICIPANT)
    Credits::GrantOrganizationTrial.call(user: creator, organization: organization)
    grant_credits!(owner: organization, amount: 5, actor: creator)

    workspace = organization.workspace
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: workspace,
      title: "Team review project",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ]
    )
    confirm_ends_on = ends_on >= Date.current ? ends_on : (Date.current + 30)
    project.update!(
      ends_on: confirm_ends_on,
      proposed_tasks: [
        {
          "title" => "Design logo",
          "summary" => "Make a logo",
          "recommended_due_date" => 7.days.from_now.to_date.iso8601,
          "submission_expectations" => "Upload a PNG"
        }
      ]
    )
    Projects::Confirm.call(project: project, user: creator)
    project.reload

    Projects::InstantJoin.call(project: project, user: participant, participant_role: "Designer")

    task = project.tasks.first
    Tasks::Assign.call(task: task, actor: creator, assignee: participant)
    Tasks::Submit.call(task: task.reload, user: participant, body: "Here is my work", links: [], signed_blob_ids: [])

    project.update_columns(ends_on: ends_on) if ends_on != confirm_ends_on

    { creator: creator, participant: participant, project: project.reload, task: task.reload, workspace: workspace }
  end

  it "lets the creator approve a submitted team task" do
    ctx = team_with_submitted_task

    updated = described_class.call(task: ctx[:task], actor: ctx[:creator], decision: "approved", feedback: "Looks good")

    expect(updated.status).to eq(Task::STATUS_APPROVED)
    expect(updated.creator_review_decision).to eq("approved")
    expect(updated.creator_reviewed_by_id).to eq(ctx[:creator].id)
    expect(updated.on_time).to eq(ctx[:task].on_time)
  end

  it "requests corrections with feedback" do
    ctx = team_with_submitted_task(ends_on: 10.days.from_now.to_date)

    updated = described_class.call(
      task: ctx[:task],
      actor: ctx[:creator],
      decision: "corrections_requested",
      feedback: "Add more detail"
    )

    expect(updated.status).to eq(Task::STATUS_CORRECTIONS_REQUESTED)
    expect(updated.creator_review_feedback).to eq("Add more detail")
  end

  it "blocks corrections when fewer than 48 hours remain before final expiration" do
    ctx = team_with_submitted_task(ends_on: Date.current - 6)

    expect {
      described_class.call(
        task: ctx[:task],
        actor: ctx[:creator],
        decision: "corrections_requested",
        feedback: "Too late"
      )
    }.to raise_error(DomainError) { |error|
      expect(error.code).to eq("corrections_window_closed")
    }
  end

  it "allows corrections during grace when more than 48h remain before final expiration" do
    ctx = team_with_submitted_task(ends_on: Date.current - 1)

    updated = described_class.call(
      task: ctx[:task],
      actor: ctx[:creator],
      decision: "corrections_requested",
      feedback: "Revise"
    )

    expect(updated.status).to eq(Task::STATUS_CORRECTIONS_REQUESTED)
  end

  it "rejects non-creators and solo projects" do
    ctx = team_with_submitted_task

    expect {
      described_class.call(task: ctx[:task], actor: ctx[:participant], decision: "approved")
    }.to raise_error(DomainError) { |error|
      expect(error.code).to eq("forbidden")
    }

    solo_creator = create_onboarded_adult(email: "solo-creator-#{SecureRandom.hex(3)}@example.com")
    grant_credits!(owner: solo_creator, amount: 2, actor: solo_creator)
    solo = Projects::CreateDraft.call(
      user: solo_creator,
      workspace: solo_creator.personal_workspace,
      title: "Solo",
      mode: Project::MODE_SOLO
    )
    solo.update!(
      ends_on: Date.current + 30,
      proposed_tasks: [
        {
          "title" => "Solo task",
          "summary" => "Do it",
          "recommended_due_date" => 7.days.from_now.to_date.iso8601,
          "submission_expectations" => "Text"
        }
      ]
    )
    Projects::Confirm.call(project: solo, user: solo_creator)
    solo_task = solo.reload.tasks.first
    Tasks::Submit.call(task: solo_task, user: solo_creator, body: "done", links: [], signed_blob_ids: [])

    expect {
      described_class.call(task: solo_task.reload, actor: solo_creator, decision: "approved")
    }.to raise_error(DomainError) { |error|
      expect(error.message).to match(/team/i)
    }
  end
end
