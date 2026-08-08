# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inbox::EvaluateOverdueAndEscalations do
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

  it "marks overdue applications, creates reminder and staff escalation for personal projects" do
    creator = create_onboarded_adult(email: "inbox-overdue-#{SecureRandom.hex(3)}@example.com")
    applicant = create_onboarded_adult(email: "applicant-#{SecureRandom.hex(3)}@example.com")
    grant_credits!(owner: creator, amount: 3, actor: creator)

    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Apply here",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_APPLICATION,
      capacity: 2,
      roles_needed: [ "Engineer" ]
    )
    Projects::Confirm.call(project: project, user: creator)

    application = Projects::SubmitApplication.call(
      project: project.reload,
      user: applicant,
      requested_role: "Engineer",
      motivation: "I want to help",
      availability_confirmed: true
    )
    application.update_columns(created_at: 73.hours.ago)

    described_class.call

    expect(application.reload.overdue_at).to be_present
    expect(InboxAlert.where(recipient_user_id: creator.id, kind: InboxAlert::KIND_CREATOR_REMINDER)).to exist
    escalation = Escalation.find_by(reason: Escalation::REASON_APPLICATION_OVERDUE, subject_id: application.id)
    expect(escalation).to be_present
    expect(escalation.target).to eq(Escalation::TARGET_STAFF)

    expect { described_class.call }.not_to change(Escalation, :count)
  end

  it "escalates org projects to organization staff alerts" do
    creator = create_onboarded_adult(email: "org-creator-#{SecureRandom.hex(3)}@example.com")
    organization = create_organization(name: "Escalation Org #{SecureRandom.hex(3)}")
    create_membership(organization: organization, user: creator, role: OrganizationMembership::ADMIN)
    Credits::GrantOrganizationTrial.call(user: creator, organization: organization)

    project = Projects::CreateDraft.call(
      user: creator,
      workspace: organization.workspace,
      title: "Org team",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_INSTANT,
      capacity: 2,
      roles_needed: [ "Designer" ]
    )
    project.update!(confirmed_at: 8.days.ago, status: Project::STATUS_ACTIVE)
    ProjectMembership.create!(
      project: project,
      user: creator,
      role: ProjectMembership::ROLE_CREATOR,
      status: ProjectMembership::STATUS_ACTIVE
    )

    described_class.call

    escalation = Escalation.find_by(reason: Escalation::REASON_NO_TASKS_CREATED, project_id: project.id)
    expect(escalation.target).to eq(Escalation::TARGET_ORGANIZATION)
    expect(
      InboxAlert.find_by(
        audience: InboxAlert::AUDIENCE_ORG_STAFF,
        organization_id: organization.id,
        kind: InboxAlert::KIND_ESCALATION
      )
    ).to be_present
  end
end
