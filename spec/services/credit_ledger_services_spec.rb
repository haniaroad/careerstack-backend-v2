# frozen_string_literal: true

require "rails_helper"

module Credits
  class SpecPackGrant
    include IdempotentGrant

    def self.call(user:, amount:)
      new(user: user, amount: amount).call
    end

    def initialize(user:, amount:)
      @user = user
      @amount = amount
    end

    def call
      ref = "pi_test_#{SecureRandom.hex(4)}"
      record_grant(
        owner: @user,
        amount: @amount,
        reason: "personal_pack_purchase",
        source: "personal_pack_purchase",
        idempotency_key: "test_purchase:#{@user.id}:#{SecureRandom.hex(4)}",
        actor_user: @user,
        stripe_payment_ref: ref
      )
      lot = CreditLot.for_owner(@user).find_by!(stripe_payment_ref: ref)
      CreditPurchase.create!(
        user: @user,
        credit_lot: lot,
        stripe_checkout_session_id: "cs_test_#{SecureRandom.hex(4)}",
        status: "completed",
        credits: @amount,
        amount_cents: CreditPurchase::PACK_AMOUNT_CENTS,
        completed_at: Time.current
      )
    end
  end
end

RSpec.describe "Credit ledger services" do
  describe Credits::Balance do
    it "sums ledger amounts for an owner" do
      user = create_onboarded_adult(email: "bal@example.com")

      expect(described_class.remaining(owner: user)).to eq(1)
      expect(described_class.summary(owner: user)).to include(
        remaining: 1,
        trial_remaining: 1,
        purchased_remaining: 0,
        owner_type: "user"
      )
    end
  end

  describe Credits::Consume do
    it "consumes one credit FIFO and is idempotent" do
      user = create_onboarded_adult(email: "c@example.com")
      lot = CreditLot.for_owner(user).sole

      entry = described_class.call(
        owner: user,
        reason: "project_create",
        idempotency_key: "consume:project:1",
        actor_user: user
      )

      expect(entry.amount).to eq(-1)
      expect(entry.event).to eq("consume")
      expect(Credits::Balance.remaining(owner: user)).to eq(0)
      expect(lot.reload.remaining).to eq(0)

      again = described_class.call(
        owner: user,
        reason: "project_create",
        idempotency_key: "consume:project:1",
        actor_user: user
      )
      expect(again.id).to eq(entry.id)
      expect(Credits::Balance.remaining(owner: user)).to eq(0)
    end

    it "raises when balance is insufficient" do
      user = create_onboarded_adult(email: "broke@example.com")
      described_class.call(owner: user, reason: "project_create", idempotency_key: "c1", actor_user: user)

      expect {
        described_class.call(owner: user, reason: "project_create", idempotency_key: "c2", actor_user: user)
      }.to raise_error(InsufficientCredits)
    end

    it "does not spend personal credits against an organization owner" do
      user = create_onboarded_adult(email: "iso@example.com")
      organization = create_organization
      Credits::GrantOrganizationTrial.call(user: user, organization: organization)

      described_class.call(
        owner: organization,
        reason: "org_project_create",
        idempotency_key: "org:c1",
        actor_user: user
      )

      expect(Credits::Balance.remaining(owner: user)).to eq(1)
      expect(Credits::Balance.remaining(owner: organization)).to eq(2)
    end

    it "allocates FIFO across trial then purchase lots" do
      user = create_onboarded_adult(email: "fifo@example.com")
      Credits::SpecPackGrant.call(user: user, amount: 3)

      described_class.call(owner: user, reason: "project_create", idempotency_key: "f1", actor_user: user)
      trial = CreditLot.for_owner(user).find_by!(source: "personal_trial")
      purchase = CreditLot.for_owner(user).find_by!(source: "personal_pack_purchase")
      expect(trial.remaining).to eq(0)
      expect(purchase.remaining).to eq(3)

      described_class.call(owner: user, reason: "project_create", idempotency_key: "f2", actor_user: user)
      expect(purchase.reload.remaining).to eq(2)
    end
  end

  describe Credits::Restore do
    it "restores a credit idempotently" do
      user = create_onboarded_adult(email: "r@example.com")
      Credits::Consume.call(owner: user, reason: "join", idempotency_key: "join:1", actor_user: user)

      entry = described_class.call(
        owner: user,
        reason: "cancellation_restore",
        idempotency_key: "restore:1",
        actor_user: user
      )

      expect(entry.amount).to eq(1)
      expect(Credits::Balance.remaining(owner: user)).to eq(1)

      again = described_class.call(
        owner: user,
        reason: "cancellation_restore",
        idempotency_key: "restore:1",
        actor_user: user
      )
      expect(again.id).to eq(entry.id)
      expect(Credits::Balance.remaining(owner: user)).to eq(1)
    end
  end

  describe Credits::ReverseUnusedPurchase do
    it "reverses only unused credits on a purchase lot" do
      user = create_onboarded_adult(email: "ref@example.com")
      purchase = Credits::SpecPackGrant.call(user: user, amount: 3)
      Credits::Consume.call(owner: user, reason: "project_create", idempotency_key: "p1", actor_user: user)
      Credits::Consume.call(owner: user, reason: "project_create", idempotency_key: "p2", actor_user: user)

      result = described_class.call(purchase: purchase.reload, actor_user: user)

      expect(result[:reversed]).to eq(2)
      expect(purchase.credit_lot.reload.remaining).to eq(0)
      expect(Credits::Balance.remaining(owner: user)).to eq(0)
    end

    it "rejects when no unused credits remain" do
      user = create_onboarded_adult(email: "ref2@example.com")
      purchase = Credits::SpecPackGrant.call(user: user, amount: 1)
      Credits::Consume.call(owner: user, reason: "project_create", idempotency_key: "x1", actor_user: user)
      Credits::Consume.call(owner: user, reason: "project_create", idempotency_key: "x2", actor_user: user)

      expect {
        described_class.call(purchase: purchase.reload)
      }.to raise_error(DomainError, /unused/i)
    end
  end

  describe Credits::History do
    it "returns append-only entries newest first" do
      user = create_onboarded_adult(email: "hist@example.com")
      Credits::Consume.call(owner: user, reason: "project_create", idempotency_key: "h1", actor_user: user)

      history = described_class.call(owner: user)
      expect(history.map { |row| row[:event] }).to eq(%w[consume grant])
      expect(history.first[:amount]).to eq(-1)
    end
  end
end
