# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Trial credit grants" do
  describe Credits::GrantPersonalTrial do
    it "grants one credit and records an idempotent ledger entry" do
      user = create_user(email: "adult@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::ADULT)

      expect(described_class.call(user: user)).to be(true)

      entry = CreditLedgerEntry.sole
      expect(entry).to have_attributes(owner: user, amount: 1, event: "grant", reason: "personal_trial")
      expect(entry.idempotency_key).to eq("personal_trial:#{user.id}")
      expect(user.reload.personal_trial_granted).to be(true)
    end

    it "does not grant a second credit on a repeat call" do
      user = create_user(email: "adult@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::ADULT)
      described_class.call(user: user)

      expect(described_class.call(user: user)).to be(false)
      expect(CreditLedgerEntry.count).to eq(1)
    end

    it "does not grant when a matching ledger entry already exists but the flag was lost" do
      user = create_user(email: "adult@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::ADULT)
      described_class.call(user: user)
      user.update_columns(personal_trial_granted: false)

      expect(described_class.call(user: user)).to be(false)
      expect(CreditLedgerEntry.count).to eq(1)
      expect(user.reload.personal_trial_granted).to be(true)
    end

    it "refuses minors" do
      user = create_user(email: "minor@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::MINOR)

      expect(described_class.call(user: user)).to be(false)
      expect(CreditLedgerEntry.count).to eq(0)
      expect(user.reload.personal_trial_granted).to be(false)
    end

    it "refuses unknown-age users" do
      user = create_user(email: "unknown@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::UNKNOWN)

      expect(described_class.call(user: user)).to be(false)
      expect(CreditLedgerEntry.count).to eq(0)
    end

    it "survives being called inside an enclosing transaction after the entry exists" do
      user = create_user(email: "adult@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::ADULT)
      described_class.call(user: user)
      user.update_columns(personal_trial_granted: false)

      ActiveRecord::Base.transaction do
        expect(described_class.call(user: user)).to be(false)
        expect(User.count).to be_positive, "the enclosing transaction must still be usable"
      end

      expect(CreditLedgerEntry.count).to eq(1)
    end
  end

  describe Credits::GrantOrganizationTrial do
    let(:user) { create_user(email: "founder@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::ADULT) }

    it "grants three pooled credits to the organization" do
      organization = create_organization

      expect(described_class.call(user: user, organization: organization)).to be(true)

      entry = CreditLedgerEntry.sole
      expect(entry).to have_attributes(owner: organization, amount: 3, reason: "organization_trial", actor_user: user)
      expect(user.reload.organization_trial_granted).to be(true)
    end

    it "is limited to one grant per adult across different organizations" do
      described_class.call(user: user, organization: create_organization(name: "First"))
      second = create_organization(name: "Second")

      expect(described_class.call(user: user, organization: second)).to be(false)
      expect(CreditLedgerEntry.where(owner: second)).to be_empty
      expect(CreditLedgerEntry.count).to eq(1)
    end

    it "keys idempotency on the creating user rather than the organization" do
      expect(described_class.idempotency_key_for(user)).to eq("organization_trial_user:#{user.id}")
    end

    it "refuses minors" do
      minor = create_user(email: "minor@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::MINOR)

      expect(described_class.call(user: minor, organization: create_organization)).to be(false)
      expect(CreditLedgerEntry.count).to eq(0)
    end
  end
end
