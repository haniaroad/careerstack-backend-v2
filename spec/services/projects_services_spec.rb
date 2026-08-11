# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Projects services" do
  def with_ends_on!(project, ends_on: Date.current + 30)
    project.update!(ends_on: ends_on)
    project
  end

  describe Projects::Confirm do
    it "activates the draft, creates membership, and consumes one credit" do
      user = create_onboarded_adult(email: "confirm@example.com")
      workspace = user.personal_workspace
      project = with_ends_on!(Projects::CreateDraft.call(user: user, workspace: workspace, title: "Portfolio site"))

      expect {
        Projects::Confirm.call(project: project, user: user)
      }.to change { Credits::Balance.remaining(owner: user) }.by(-1)

      project.reload
      expect(project.status).to eq(Project::STATUS_ACTIVE)
      expect(project.memberships.active.find_by(user: user)).to be_present
    end

    it "rejects confirm without ends_on" do
      user = create_onboarded_adult(email: "no-end@example.com")
      project = Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "No end")

      expect {
        Projects::Confirm.call(project: project, user: user)
      }.to raise_error(DomainError) { |e|
        expect(e.code).to eq("validation_error")
        expect(e.message).to match(/ends_on/i)
      }
      expect(project.reload.status).to eq(Project::STATUS_DRAFT)
      expect(Credits::Balance.remaining(owner: user)).to eq(1)
    end

    it "is idempotent on double confirm after activation" do
      user = create_onboarded_adult(email: "idem@example.com")
      project = with_ends_on!(Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Once"))
      Projects::Confirm.call(project: project, user: user)

      expect {
        Projects::Confirm.call(project: project.reload, user: user)
      }.to raise_error(DomainError, /Only draft/)
      expect(Credits::Balance.remaining(owner: user)).to eq(0)
    end

    it "rejects insufficient credits without activating" do
      user = create_onboarded_adult(email: "broke@example.com")
      project = with_ends_on!(Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Need credits"))
      Credits::Consume.call(
        owner: user,
        amount: 1,
        reason: "project_create",
        idempotency_key: "pre-spend-#{user.id}",
        actor_user: user
      )

      expect {
        Projects::Confirm.call(project: project, user: user)
      }.to raise_error(InsufficientCredits)

      expect(project.reload.status).to eq(Project::STATUS_DRAFT)
      expect(project.memberships.count).to eq(0)
    end

    it "blocks a second active participation" do
      user = create_onboarded_adult(email: "busy@example.com")
      first = with_ends_on!(Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "First"))
      Projects::Confirm.call(project: first, user: user)

      second = with_ends_on!(Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Second"))
      ref = "pi_test_#{SecureRandom.hex(4)}"
      lot = CreditLot.create!(
        owner: user,
        source: "personal_pack_purchase",
        original_amount: 1,
        remaining: 1,
        stripe_payment_ref: ref,
        granted_at: Time.current
      )
      CreditLedgerEntry.create!(
        owner: user,
        event: "grant",
        amount: 1,
        actor_user: user,
        reason: "personal_pack_purchase",
        idempotency_key: "topup-#{user.id}",
        credit_lot: lot
      )

      expect {
        Projects::Confirm.call(project: second, user: user)
      }.to raise_error(ActiveParticipationConflict)

      expect(second.reload.status).to eq(Project::STATUS_DRAFT)
    end
  end

  describe Projects::Cancel do
    it "cancels an active solo project and restores one credit" do
      user = create_onboarded_adult(email: "cancel@example.com")
      project = with_ends_on!(Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Cancel me"))
      Projects::Confirm.call(project: project, user: user)

      expect {
        Projects::Cancel.call(project: project, user: user)
      }.to change { Credits::Balance.remaining(owner: user) }.by(1)

      expect(project.reload.status).to eq(Project::STATUS_CANCELLED)
      expect(project.memberships.active.count).to eq(0)
    end

    it "does not double-restore on repeated cancel" do
      user = create_onboarded_adult(email: "cancel2@example.com")
      project = with_ends_on!(Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Cancel twice"))
      Projects::Confirm.call(project: project, user: user)
      Projects::Cancel.call(project: project, user: user)

      expect {
        Projects::Cancel.call(project: project.reload, user: user)
      }.not_to change { Credits::Balance.remaining(owner: user) }
    end
  end

  describe Projects::CreateDraft do
    it "does not consume credits" do
      user = create_onboarded_adult(email: "draft@example.com")
      expect {
        Projects::CreateDraft.call(user: user, workspace: user.personal_workspace, title: "Draft only")
      }.not_to change { Credits::Balance.remaining(owner: user) }
    end
  end
end
