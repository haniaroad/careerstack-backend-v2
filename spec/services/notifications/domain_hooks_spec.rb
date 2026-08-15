# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Notification domain hooks" do
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

  def setup_team(joining_mode: Project::JOINING_INSTANT)
    creator = create_onboarded_adult(email: "hook-creator-#{SecureRandom.hex(3)}@example.com")
    participant = create_onboarded_adult(email: "hook-member-#{SecureRandom.hex(3)}@example.com")
    organization = create_organization(name: "Hook Org #{SecureRandom.hex(3)}")
    create_membership(organization: organization, user: creator, role: OrganizationMembership::ADMIN)
    create_membership(organization: organization, user: participant, role: OrganizationMembership::PARTICIPANT)
    Credits::GrantOrganizationTrial.call(user: creator, organization: organization)
    grant_credits!(owner: organization, amount: 5, actor: creator)
    program = create_program(organization: organization)

    project = Projects::CreateDraft.call(
      user: creator,
      workspace: organization.workspace,
      title: "Hook team",
      mode: Project::MODE_TEAM,
      joining_mode: joining_mode,
      capacity: 3,
      roles_needed: [ "Designer" ],
      program_id: program.id
    )
    project.update!(
      ends_on: Date.current + 30,
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

    {
      creator: creator,
      participant: participant,
      organization: organization,
      project: project.reload
    }
  end

  it "notifies the assignee on assign and does not notify the actor" do
    ctx = setup_team
    Projects::InstantJoin.call(project: ctx[:project], user: ctx[:participant], participant_role: "Designer")
    task = ctx[:project].tasks.first

    Tasks::Assign.call(task: task, actor: ctx[:creator], assignee: ctx[:participant])

    expect(Notification.where(event_key: "task_assigned", recipient_user: ctx[:participant])).to exist
    expect(Notification.where(event_key: "task_assigned", recipient_user: ctx[:creator])).not_to exist
  end

  it "notifies a project invitee and not the inviter" do
    ctx = setup_team(joining_mode: Project::JOINING_INVITE_ONLY)
    invitation = Projects::CreateInvitation.call(
      project: ctx[:project],
      inviter: ctx[:creator],
      invitee: ctx[:participant],
      requested_role: "Designer"
    )

    expect(invitation).to be_present
    expect(Notification.where(event_key: "project_invitation", recipient_user: ctx[:participant])).to exist
    expect(Notification.where(event_key: "project_invitation", recipient_user: ctx[:creator])).not_to exist
  end

  it "notifies the applicant of a decision and not the deciding creator" do
    ctx = setup_team(joining_mode: Project::JOINING_APPLICATION)
    application = Projects::SubmitApplication.call(
      project: ctx[:project],
      user: ctx[:participant],
      requested_role: "Designer",
      motivation: "I can design",
      availability_confirmed: true
    )
    expect(Notification.where(event_key: "application_received", recipient_user: ctx[:creator])).to exist
    expect(Notification.where(event_key: "application_received", recipient_user: ctx[:participant])).not_to exist

    Projects::ApproveApplication.call(application: application, user: ctx[:creator])
    expect(Notification.where(event_key: "application_decision", recipient_user: ctx[:participant])).to exist
    expect(Notification.where(event_key: "application_decision", recipient_user: ctx[:creator])).not_to exist
  end

  it "creates a staff email-only escalation for Personal projects" do
    creator = create_onboarded_adult(email: "esc-creator-#{SecureRandom.hex(3)}@example.com")
    applicant = create_onboarded_adult(email: "esc-app-#{SecureRandom.hex(3)}@example.com")
    grant_credits!(owner: creator, amount: 3, actor: creator)

    project = Projects::CreateDraft.call(
      user: creator,
      workspace: creator.personal_workspace,
      title: "Personal apply",
      mode: Project::MODE_TEAM,
      joining_mode: Project::JOINING_APPLICATION,
      capacity: 2,
      roles_needed: [ "Engineer" ]
    )
    project.update!(ends_on: Date.current + 30)
    Projects::Confirm.call(project: project, user: creator)
    application = Projects::SubmitApplication.call(
      project: project.reload,
      user: applicant,
      requested_role: "Engineer",
      motivation: "Please",
      availability_confirmed: true
    )
    application.update_columns(created_at: 73.hours.ago)

    Inbox::EvaluateOverdueAndEscalations.call

    staff = Notification.find_by(event_key: "escalation_created", recipient_user_id: nil)
    expect(staff).to be_present
    expect(staff.recipient_email).to eq(Notifications::Catalog::STAFF_INBOX)
    expect(Notification.where(event_key: "escalation_created", recipient_user: creator)).not_to exist
    expect(Notification.where(event_key: "application_overdue", recipient_user: creator)).to exist
  end

  it "emits a purchase receipt to the buyer" do
    user = create_onboarded_adult(email: "buyer-#{SecureRandom.hex(3)}@example.com")
    session = Struct.new(:id, :metadata, :client_reference_id, :payment_intent, keyword_init: true).new(
      id: "cs_test_#{SecureRandom.hex(4)}",
      metadata: { "careerstack_user_id" => user.id },
      client_reference_id: nil,
      payment_intent: "pi_test_#{SecureRandom.hex(4)}"
    )

    Billing::ProcessWebhook.new(payload: "{}", signature: "sig").send(:complete_checkout!, session, "evt_#{SecureRandom.hex(4)}")

    expect(Notification.where(event_key: "purchase_receipt", recipient_user: user)).to exist
  end
end
