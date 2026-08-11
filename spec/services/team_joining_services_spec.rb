# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Team joining services" do
  # Mirrors projects_services_spec CreditLot + CreditLedgerEntry top-ups when trial balance is short.
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
      idempotency_key: "topup-#{owner.class.name.underscore}-#{owner.id}-#{SecureRandom.hex(4)}",
      credit_lot: lot
    )
    lot
  end

  def setup_org_team(creator_email:, participant_emails: [], capacity: 3, joining_mode: Project::JOINING_INSTANT,
                     roles_needed: [ "Designer" ], proposed_tasks: nil)
    creator = create_onboarded_adult(email: creator_email)
    organization = create_organization(name: "Team Org #{SecureRandom.hex(3)}")
    create_membership(organization: organization, user: creator, role: OrganizationMembership::ADMIN)
    Credits::GrantOrganizationTrial.call(user: creator, organization: organization)

    participants = participant_emails.map do |email|
      user = create_onboarded_adult(email: email)
      create_membership(organization: organization, user: user, role: OrganizationMembership::PARTICIPANT)
      user
    end

    workspace = organization.workspace
    project = Projects::CreateDraft.call(
      user: creator,
      workspace: workspace,
      title: "Team project",
      mode: Project::MODE_TEAM,
      joining_mode: joining_mode,
      capacity: capacity,
      roles_needed: roles_needed
    )
    if proposed_tasks
      project.update!(proposed_tasks: proposed_tasks)
    end

    {
      creator: creator,
      organization: organization,
      workspace: workspace,
      project: project,
      participants: participants
    }
  end

  def confirm_team!(ctx)
    ctx[:project].update!(ends_on: Date.current + 30) if ctx[:project].ends_on.blank?
    Projects::Confirm.call(project: ctx[:project], user: ctx[:creator])
    ctx[:project].reload
  end

  describe Projects::CreateDraft do
    it "requires joining_mode, capacity, and roles for team mode" do
      user = create_onboarded_adult(email: "team-draft@example.com")
      workspace = user.personal_workspace

      expect {
        Projects::CreateDraft.call(
          user: user,
          workspace: workspace,
          title: "No joining mode",
          mode: Project::MODE_TEAM,
          capacity: 2,
          roles_needed: [ "Engineer" ]
        )
      }.to raise_error(DomainError, /Joining mode is required/)

      expect {
        Projects::CreateDraft.call(
          user: user,
          workspace: workspace,
          title: "Bad capacity",
          mode: Project::MODE_TEAM,
          joining_mode: Project::JOINING_INSTANT,
          capacity: 0,
          roles_needed: [ "Engineer" ]
        )
      }.to raise_error(DomainError, /Capacity must be between 1 and 5/)

      expect {
        Projects::CreateDraft.call(
          user: user,
          workspace: workspace,
          title: "No roles",
          mode: Project::MODE_TEAM,
          joining_mode: Project::JOINING_INSTANT,
          capacity: 2,
          roles_needed: []
        )
      }.to raise_error(DomainError, /At least one role is required/)
    end

    it "creates a team draft when joining fields are valid" do
      user = create_onboarded_adult(email: "team-draft-ok@example.com")

      project = Projects::CreateDraft.call(
        user: user,
        workspace: user.personal_workspace,
        title: "Valid team draft",
        mode: Project::MODE_TEAM,
        joining_mode: Project::JOINING_APPLICATION,
        capacity: 3,
        roles_needed: [ "PM", "Engineer" ]
      )

      expect(project).to have_attributes(
        mode: Project::MODE_TEAM,
        joining_mode: Project::JOINING_APPLICATION,
        capacity: 3,
        roles_needed: [ "PM", "Engineer" ],
        status: Project::STATUS_DRAFT
      )
      expect(Credits::Balance.remaining(owner: user)).to eq(1)
    end
  end

  describe Projects::Confirm do
    it "activates a team project, consumes one create credit, and leaves tasks unassigned" do
      ctx = setup_org_team(
        creator_email: "team-confirm@example.com",
        proposed_tasks: [
          { "title" => "Ship homepage", "summary" => "Build it", "recommended_due_date" => (Date.current + 7).iso8601 }
        ]
      )

      expect {
        confirm_team!(ctx)
      }.to change { Credits::Balance.remaining(owner: ctx[:organization]) }.by(-1)

      project = ctx[:project]
      expect(project.status).to eq(Project::STATUS_ACTIVE)
      expect(project.memberships.active.find_by(user: ctx[:creator], role: ProjectMembership::ROLE_CREATOR)).to be_present
      expect(project.tasks.count).to eq(1)
      expect(project.tasks.first.assignee_id).to be_nil
    end
  end

  describe Projects::CreateMembership do
    it "consumes one join credit via InstantJoin" do
      ctx = setup_org_team(
        creator_email: "instant-creator@example.com",
        participant_emails: [ "instant-joiner@example.com" ],
        capacity: 2
      )
      confirm_team!(ctx)
      joiner = ctx[:participants].first

      expect {
        Projects::InstantJoin.call(project: ctx[:project], user: joiner, participant_role: "Designer")
      }.to change { Credits::Balance.remaining(owner: ctx[:organization]) }.by(-1)

      membership = ctx[:project].memberships.active.find_by!(user: joiner)
      expect(membership).to have_attributes(
        role: ProjectMembership::ROLE_PARTICIPANT,
        participant_role: "Designer",
        join_source: ProjectMembership::JOIN_SOURCE_INSTANT
      )
    end

    it "blocks a second active participation" do
      first = setup_org_team(
        creator_email: "busy-creator-a@example.com",
        participant_emails: [ "busy-joiner@example.com" ],
        capacity: 2
      )
      confirm_team!(first)
      joiner = first[:participants].first
      Projects::InstantJoin.call(project: first[:project], user: joiner, participant_role: "Designer")

      second = setup_org_team(
        creator_email: "busy-creator-b@example.com",
        capacity: 2
      )
      create_membership(organization: second[:organization], user: joiner, role: OrganizationMembership::PARTICIPANT)
      confirm_team!(second)
      grant_credits!(owner: second[:organization], amount: 1, actor: second[:creator])

      expect {
        Projects::InstantJoin.call(project: second[:project], user: joiner, participant_role: "Engineer")
      }.to raise_error(ActiveParticipationConflict)
    end

    it "raises capacity_full DomainError when seats are gone" do
      ctx = setup_org_team(
        creator_email: "cap-creator@example.com",
        participant_emails: [ "cap-one@example.com", "cap-two@example.com" ],
        capacity: 1
      )
      confirm_team!(ctx)
      Projects::InstantJoin.call(project: ctx[:project], user: ctx[:participants].first, participant_role: "Designer")

      expect {
        Projects::InstantJoin.call(project: ctx[:project], user: ctx[:participants].second, participant_role: "Engineer")
      }.to raise_error(DomainError) { |error|
        expect(error.code).to eq("capacity_full")
        expect(error.status).to eq(:conflict)
      }
    end

    it "rejects join when the workspace has insufficient credits" do
      ctx = setup_org_team(
        creator_email: "broke-creator@example.com",
        participant_emails: [ "broke-joiner@example.com" ],
        capacity: 2
      )
      confirm_team!(ctx)
      remaining = Credits::Balance.remaining(owner: ctx[:organization])
      Credits::Consume.call(
        owner: ctx[:organization],
        amount: remaining,
        reason: "org_project_create",
        idempotency_key: "drain-#{ctx[:organization].id}",
        actor_user: ctx[:creator]
      )

      expect {
        Projects::InstantJoin.call(
          project: ctx[:project],
          user: ctx[:participants].first,
          participant_role: "Designer"
        )
      }.to raise_error(InsufficientCredits)

      expect(ctx[:project].memberships.active.participants.count).to eq(0)
    end
  end

  describe "application flow" do
    it "SubmitApplication does not consume credit; ApproveApplication consumes and creates membership" do
      ctx = setup_org_team(
        creator_email: "app-creator@example.com",
        participant_emails: [ "app-applicant@example.com" ],
        joining_mode: Project::JOINING_APPLICATION,
        capacity: 2
      )
      confirm_team!(ctx)
      applicant = ctx[:participants].first
      before = Credits::Balance.remaining(owner: ctx[:organization])

      application = Projects::SubmitApplication.call(
        project: ctx[:project],
        user: applicant,
        requested_role: "Designer",
        motivation: "I want to help ship this",
        availability_confirmed: true,
        skills: [ "Figma" ]
      )

      expect(Credits::Balance.remaining(owner: ctx[:organization])).to eq(before)
      expect(application.status).to eq(ProjectApplication::STATUS_PENDING)

      expect {
        Projects::ApproveApplication.call(application: application, user: ctx[:creator])
      }.to change { Credits::Balance.remaining(owner: ctx[:organization]) }.by(-1)

      application.reload
      expect(application.status).to eq(ProjectApplication::STATUS_APPROVED)
      expect(ctx[:project].memberships.active.find_by(user: applicant)).to be_present
    end

    it "RejectApplication requires a reason and consumes no credit" do
      ctx = setup_org_team(
        creator_email: "rej-creator@example.com",
        participant_emails: [ "rej-applicant@example.com" ],
        joining_mode: Project::JOINING_APPLICATION,
        capacity: 2
      )
      confirm_team!(ctx)
      applicant = ctx[:participants].first
      application = Projects::SubmitApplication.call(
        project: ctx[:project],
        user: applicant,
        requested_role: "Designer",
        motivation: "Please accept me",
        availability_confirmed: true
      )
      before = Credits::Balance.remaining(owner: ctx[:organization])

      expect {
        Projects::RejectApplication.call(application: application, user: ctx[:creator], reason: "")
      }.to raise_error(DomainError, /Rejection reason is required/)

      rejected = Projects::RejectApplication.call(
        application: application,
        user: ctx[:creator],
        reason: "Role already filled"
      )

      expect(rejected.status).to eq(ProjectApplication::STATUS_REJECTED)
      expect(rejected.rejection_reason).to eq("Role already filled")
      expect(Credits::Balance.remaining(owner: ctx[:organization])).to eq(before)
      expect(ctx[:project].memberships.active.participants.count).to eq(0)
    end
  end

  describe "invitation flow" do
    it "CreateInvitation + AcceptInvitation creates membership and consumes one credit" do
      ctx = setup_org_team(
        creator_email: "inv-creator@example.com",
        participant_emails: [ "inv-invitee@example.com" ],
        joining_mode: Project::JOINING_INVITE_ONLY,
        capacity: 2
      )
      confirm_team!(ctx)
      invitee = ctx[:participants].first

      invitation = Projects::CreateInvitation.call(
        project: ctx[:project],
        inviter: ctx[:creator],
        invitee: invitee,
        requested_role: "Engineer"
      )
      expect(invitation.status).to eq(ProjectInvitation::STATUS_PENDING)

      expect {
        Projects::AcceptInvitation.call(invitation: invitation, user: invitee)
      }.to change { Credits::Balance.remaining(owner: ctx[:organization]) }.by(-1)

      expect(invitation.reload.status).to eq(ProjectInvitation::STATUS_ACCEPTED)
      membership = ctx[:project].memberships.active.find_by!(user: invitee)
      expect(membership.join_source).to eq(ProjectMembership::JOIN_SOURCE_INVITE)
      expect(membership.participant_role).to eq("Engineer")
    end
  end

  describe Projects::Leave do
    it "unassigns pending tasks and does not restore credits" do
      ctx = setup_org_team(
        creator_email: "leave-creator@example.com",
        participant_emails: [ "leave-member@example.com" ],
        capacity: 2,
        proposed_tasks: [
          { "title" => "Task A", "summary" => "Do A", "recommended_due_date" => (Date.current + 5).iso8601 }
        ]
      )
      confirm_team!(ctx)
      member = ctx[:participants].first
      Projects::InstantJoin.call(project: ctx[:project], user: member, participant_role: "Designer")
      task = ctx[:project].tasks.first
      Tasks::Assign.call(task: task, actor: ctx[:creator], assignee: member)

      balance_before = Credits::Balance.remaining(owner: ctx[:organization])

      Projects::Leave.call(
        project: ctx[:project],
        user: member,
        reason_category: "personal_reason",
        reason_detail: "Need a break"
      )

      expect(task.reload.assignee_id).to be_nil
      expect(ctx[:project].memberships.find_by!(user: member).status).to eq(ProjectMembership::STATUS_DEPARTED)
      expect(Credits::Balance.remaining(owner: ctx[:organization])).to eq(balance_before)
    end
  end

  describe Projects::Cancel do
    it "restores join credits to current participants only, not creator create credit" do
      ctx = setup_org_team(
        creator_email: "cancel-creator@example.com",
        participant_emails: [ "cancel-active@example.com", "cancel-departed@example.com" ],
        capacity: 3
      )
      confirm_team!(ctx)
      active_member, departed = ctx[:participants]
      Projects::InstantJoin.call(project: ctx[:project], user: active_member, participant_role: "Designer")
      Projects::InstantJoin.call(project: ctx[:project], user: departed, participant_role: "Engineer")
      Projects::Leave.call(project: ctx[:project], user: departed, reason_category: "schedule_conflict")

      # After confirm (-1) and two joins (-2): trial 3 → 0. Departed already left with no restore.
      expect(Credits::Balance.remaining(owner: ctx[:organization])).to eq(0)

      expect {
        Projects::Cancel.call(project: ctx[:project], user: ctx[:creator])
      }.to change { Credits::Balance.remaining(owner: ctx[:organization]) }.by(1)

      expect(ctx[:project].reload.status).to eq(Project::STATUS_CANCELLED)
      expect(ctx[:project].memberships.active.count).to eq(0)

      restore_entries = CreditLedgerEntry.where(
        owner: ctx[:organization],
        event: "restore",
        reason: "membership_cancel_restore"
      )
      expect(restore_entries.count).to eq(1)
      expect(CreditLedgerEntry.where(owner: ctx[:organization], reason: "cancellation_restore").count).to eq(0)
    end
  end

  describe "mode conversion" do
    it "ConvertToTeam sets mode team and disables solo AI submit path" do
      creator = create_onboarded_adult(email: "convert-team@example.com")
      organization = create_organization(name: "Convert Org")
      create_membership(organization: organization, user: creator, role: OrganizationMembership::ADMIN)
      Credits::GrantOrganizationTrial.call(user: creator, organization: organization)

      project = Projects::CreateDraft.call(
        user: creator,
        workspace: organization.workspace,
        title: "Solo first",
        mode: Project::MODE_SOLO
      )
    project.update!(
      ends_on: Date.current + 30,
      proposed_tasks: [
        { "title" => "Solo task", "summary" => "Work", "recommended_due_date" => (Date.current + 3).iso8601 }
      ]
    )
    Projects::Confirm.call(project: project, user: creator)
      expect(project.reload.solo?).to eq(true)
      expect(project.tasks.first.assignee_id).to eq(creator.id)

      converted = Projects::ConvertToTeam.call(
        project: project,
        user: creator,
        joining_mode: Project::JOINING_INSTANT,
        capacity: 2,
        roles_needed: [ "Designer" ]
      )

      expect(converted.mode).to eq(Project::MODE_TEAM)
      expect(converted.joining_mode).to eq(Project::JOINING_INSTANT)
      expect(converted.solo?).to eq(false)
      expect(converted.tasks.first.assignee_id).to be_nil
    end

    it "ConvertToSolo is blocked after a participant has joined" do
      ctx = setup_org_team(
        creator_email: "convert-solo@example.com",
        participant_emails: [ "convert-joiner@example.com" ],
        capacity: 2
      )
      confirm_team!(ctx)

      solo = Projects::ConvertToSolo.call(project: ctx[:project], user: ctx[:creator])
      expect(solo.mode).to eq(Project::MODE_SOLO)

      # Re-convert to team, join, then ConvertToSolo must fail
      Projects::ConvertToTeam.call(
        project: solo,
        user: ctx[:creator],
        joining_mode: Project::JOINING_INSTANT,
        capacity: 2,
        roles_needed: [ "Designer" ]
      )
      Projects::InstantJoin.call(
        project: ctx[:project].reload,
        user: ctx[:participants].first,
        participant_role: "Designer"
      )

      expect {
        Projects::ConvertToSolo.call(project: ctx[:project].reload, user: ctx[:creator])
      }.to raise_error(DomainError, /Cannot convert to solo after a participant has joined/)
    end
  end

  describe "task assignment and submit" do
    it "creator assigns a participant; cannot assign the creator; team submit skips AI review enqueue" do
      ctx = setup_org_team(
        creator_email: "assign-creator@example.com",
        participant_emails: [ "assign-member@example.com" ],
        capacity: 2,
        proposed_tasks: [
          { "title" => "Deliverable", "summary" => "Ship it", "recommended_due_date" => (Date.current + 4).iso8601 }
        ]
      )
      confirm_team!(ctx)
      member = ctx[:participants].first
      Projects::InstantJoin.call(project: ctx[:project], user: member, participant_role: "Designer")
      task = ctx[:project].tasks.first

      expect {
        Tasks::Assign.call(task: task, actor: ctx[:creator], assignee: ctx[:creator])
      }.to raise_error(DomainError, /Creator cannot be assigned/)

      Tasks::Assign.call(task: task, actor: ctx[:creator], assignee: member)
      expect(task.reload.assignee_id).to eq(member.id)

      result = Tasks::Submit.call(
        task: task.reload,
        user: member,
        body: "Here is my team submission evidence",
        enqueue_review: true
      )

      expect(result[:task].status).to eq(Task::STATUS_SUBMITTED)
      expect(result[:review]).to be_nil
      expect(task.ai_reviews.count).to eq(0)
    end
  end
end
