# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Peer review services" do
  def grant_credits!(owner:, amount:, actor:)
    lot = CreditLot.create!(
      owner: owner,
      source: "personal_pack_purchase",
      original_amount: amount,
      remaining: amount,
      stripe_payment_ref: "pi_test_#{SecureRandom.hex(4)}",
      granted_at: Time.current
    )
    CreditLedgerEntry.create!(
      owner: owner,
      event: "grant",
      amount: amount,
      actor_user: actor,
      reason: "personal_pack_purchase",
      idempotency_key: "topup-#{SecureRandom.hex(4)}",
      credit_lot: lot
    )
  end

  def completed_team!(skills: [ "Ruby" ])
    creator = create_onboarded_adult(email: "pr-svc-c-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "pr-svc-p-#{SecureRandom.hex(3)}@example.com")
    grant_credits!(owner: creator, amount: 3, actor: creator)
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Service team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 3,
      roles_needed: [ "Designer" ]
    )
    project.update!(
      ends_on: Date.current + 30,
      skills: skills,
      proposed_tasks: [
        {
          "title" => "Ship it",
          "summary" => "Do the work",
          "recommended_due_date" => (Date.current + 5).iso8601,
          "submission_expectations" => "Text"
        }
      ]
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
    project.tasks.find_each do |task|
      task.update!(assignee_id: participant.id, status: Task::STATUS_APPROVED)
    end
    Projects::Lifecycle::Evaluate.call(project: project.reload)
    { creator: creator, participant: participant, project: project.reload }
  end

  it "opens directed slots on team completion and skips solo" do
    ctx = completed_team!
    expect(PeerReview.where(project: ctx[:project]).count).to eq(2)

    solo_user = create_onboarded_adult(email: "pr-solo-#{SecureRandom.hex(3)}@example.com")
    grant_credits!(owner: solo_user, amount: 3, actor: solo_user)
    solo = Projects::CreateDraft.call(user: solo_user, workspace: solo_user.personal_workspace, title: "Solo")
    solo.update!(
      ends_on: Date.current + 14,
      proposed_tasks: [ { "title" => "One", "summary" => "x", "recommended_due_date" => (Date.current + 5).iso8601, "submission_expectations" => "Text" } ]
    )
    Projects::Confirm.call(project: solo, user: solo_user)
    solo.reload.tasks.find_each { |task| task.update!(status: Task::STATUS_APPROVED) }
    Projects::Lifecycle::Evaluate.call(project: solo.reload)
    expect(PeerReview.where(project: solo.reload)).to be_empty
  end

  it "does not open slots during grace and excludes departed members" do
    creator = create_onboarded_adult(email: "pr-grace-c-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "pr-grace-p-#{SecureRandom.hex(3)}@example.com")
    departed = create_onboarded_adult(email: "pr-grace-d-#{SecureRandom.hex(3)}@example.com")
    grant_credits!(owner: creator, amount: 3, actor: creator)
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Grace team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 4,
      roles_needed: [ "Designer" ]
    )
    project.update!(ends_on: Date.current + 30, proposed_tasks: [ { "title" => "One", "summary" => "x", "recommended_due_date" => (Date.current + 5).iso8601, "submission_expectations" => "Text" } ])
    Projects::Confirm.call(project: project, user: creator)
    ProjectMembership.create!(project: project.reload, user: participant, role: ProjectMembership::ROLE_PARTICIPANT, status: ProjectMembership::STATUS_ACTIVE, participant_role: "Designer", join_source: ProjectMembership::JOIN_SOURCE_INSTANT)
    ProjectMembership.create!(project: project, user: departed, role: ProjectMembership::ROLE_PARTICIPANT, status: ProjectMembership::STATUS_DEPARTED, participant_role: "Designer", join_source: ProjectMembership::JOIN_SOURCE_INSTANT)

    project.update_columns(ends_on: Date.current - 1)
    expect(project.reload.grace_period?).to eq(true)
    expect {
      PeerReviews::Submit.call(review: PeerReview.new(project: project, reviewer: creator, reviewee: participant), actor: creator, rating: 4, comment: "Nope")
    }.to raise_error(DomainError)

    project.tasks.find_each { |task| task.update!(assignee_id: participant.id, status: Task::STATUS_APPROVED) }
    Projects::Lifecycle::Evaluate.call(project: project.reload)
    involved = PeerReview.where(project: project.reload).flat_map { |row| [ row.reviewer_id, row.reviewee_id ] }.uniq
    expect(involved).to contain_exactly(creator.id, participant.id)
    expect(involved).not_to include(departed.id)
  end

  it "submits immutably, records contribution, and raises peer_confirmed" do
    ctx = completed_team!
    slot = PeerReview.find_by!(project: ctx[:project], reviewer: ctx[:participant], reviewee: ctx[:creator])
    submitted = PeerReviews::Submit.call(review: slot, actor: ctx[:participant], rating: 5, comment: "Great creator notes")

    expect(submitted).to be_completed
    expect(ContributionEvent.where(user: ctx[:participant], kind: ContributionEvent::KIND_PEER_REVIEW_SUBMITTED)).to be_present
    expect(Profiles::Evidence.call(user: ctx[:creator])[:skills].any? { |row| row[:level] == "peer_confirmed" }).to eq(true)
    expect {
      PeerReviews::Submit.call(review: submitted.reload, actor: ctx[:participant], rating: 1, comment: "changed")
    }.to raise_error(DomainError)
    expect(submitted.reload.rating).to eq(5)
    expect(ctx[:creator].reload).to have_attributes(id: ctx[:creator].id)
    stats = Profiles::Stats.call(user: ctx[:creator])
    expect(stats[:on_time_submission_rate]).to be_nil
  end

  it "backfills completed team projects without emitting" do
    creator = create_onboarded_adult(email: "pr-bf-c-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "pr-bf-p-#{SecureRandom.hex(3)}@example.com")
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Already done",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 2,
      roles_needed: [ "Designer" ]
    )
    project.update!(status: Project::STATUS_COMPLETED, completed_at: 1.day.ago, ends_on: Date.current + 14)
    ProjectMembership.create!(project: project, user: creator, role: ProjectMembership::ROLE_CREATOR, status: ProjectMembership::STATUS_ACTIVE)
    ProjectMembership.create!(project: project, user: participant, role: ProjectMembership::ROLE_PARTICIPANT, status: ProjectMembership::STATUS_ACTIVE, participant_role: "Designer", join_source: ProjectMembership::JOIN_SOURCE_INSTANT)

    expect {
      PeerReviews::Backfill.call
    }.not_to change { Notification.where(event_key: "peer_review_request").count }
    expect(PeerReview.where(project: project).count).to eq(2)
  end
end
