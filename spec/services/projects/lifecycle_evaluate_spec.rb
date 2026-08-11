# frozen_string_literal: true

require "rails_helper"

RSpec.describe Projects::Lifecycle::Evaluate do
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

  def solo_with_tasks!(task_count: 1, ends_on: Date.current + 14)
    user = create_onboarded_adult(email: "eval-#{SecureRandom.hex(3)}@example.com")
    grant_credits!(owner: user, amount: 3, actor: user)
    project = Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Eval")
    project.update!(
      ends_on: ends_on,
      proposed_tasks: task_count.times.map { |i|
        {
          "title" => "Task #{i + 1}",
          "summary" => "Do it",
          "recommended_due_date" => (Date.current + 5).iso8601,
          "submission_expectations" => "Text"
        }
      }
    )
    Projects::Confirm.call(project: project, user: user)
    { user: user, project: project.reload }
  end

  it "completes when all tasks are assigned and approved" do
    ctx = solo_with_tasks!(task_count: 2)
    remaining_before = Credits::Balance.remaining(owner: ctx[:user])
    ctx[:project].tasks.find_each { |t| t.update!(status: Task::STATUS_APPROVED) }

    described_class.call(project: ctx[:project])

    expect(ctx[:project].reload.status).to eq(Project::STATUS_COMPLETED)
    expect(ctx[:project].completed_at).to be_present
    expect(Credits::Balance.remaining(owner: ctx[:user])).to eq(remaining_before)
  end

  it "does not complete an empty project" do
    user = create_onboarded_adult(email: "empty-#{SecureRandom.hex(3)}@example.com")
    project = Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Empty")
    project.update!(ends_on: Date.current + 14, proposed_tasks: [])
    Projects::Confirm.call(project: project, user: user)

    described_class.call(project: project.reload)
    expect(project.reload.status).to eq(Project::STATUS_ACTIVE)
  end

  it "expires past final expiration, marks incomplete, and does not restore credits" do
    ctx = solo_with_tasks!(task_count: 2)
    remaining_before = Credits::Balance.remaining(owner: ctx[:user])
    tasks = ctx[:project].tasks.order(:position).to_a
    tasks.first.update!(status: Task::STATUS_APPROVED)
    tasks.second.update!(status: Task::STATUS_SUBMITTED)
    ctx[:project].update_columns(ends_on: Date.current - 8)

    described_class.call(project: ctx[:project].reload)

    project = ctx[:project].reload
    expect(project.status).to eq(Project::STATUS_EXPIRED)
    expect(project.expired_at).to be_present
    expect(tasks.first.reload.status).to eq(Task::STATUS_APPROVED)
    expect(tasks.second.reload.status).to eq(Task::STATUS_INCOMPLETE)
    expect(Credits::Balance.remaining(owner: ctx[:user])).to eq(remaining_before)
    expect(InboxAlert.where("idempotency_key LIKE ?", "lifecycle:expired:#{project.id}%").count).to be >= 1
  end

  it "creates idempotent grace and ending_soon alerts" do
    ctx = solo_with_tasks!(ends_on: Date.current + 5)
    described_class.call(project: ctx[:project])
    described_class.call(project: ctx[:project].reload)
    expect(InboxAlert.where("idempotency_key LIKE ?", "lifecycle:ending_soon:#{ctx[:project].id}%").count).to eq(1)

    ctx[:project].update_columns(ends_on: Date.current - 1)
    described_class.call(project: ctx[:project].reload)
    described_class.call(project: ctx[:project].reload)
    expect(InboxAlert.where("idempotency_key LIKE ?", "lifecycle:grace:#{ctx[:project].id}%").count).to eq(1)
  end

  it "expires pending applications when entering grace" do
    creator = create_onboarded_adult(email: "grace-c-#{SecureRandom.hex(3)}@example.com")
    applicant = create_onboarded_adult(email: "grace-a-#{SecureRandom.hex(3)}@example.com")
    grant_credits!(owner: creator, amount: 2, actor: creator)
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Apps",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_APPLICATION,
      capacity: 3,
      roles_needed: [ "Engineer" ]
    )
    project.update!(ends_on: Date.current + 14)
    Projects::Confirm.call(project: project, user: creator)
    application = Projects::SubmitApplication.call(
      project: project.reload,
      user: applicant,
      requested_role: "Engineer",
      motivation: "Hi",
      availability_confirmed: true
    )

    project.update_columns(ends_on: Date.current - 1)
    described_class.call(project: project.reload)

    expect(application.reload.status).to eq(ProjectApplication::STATUS_EXPIRED)
  end
end
