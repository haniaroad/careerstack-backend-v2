# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invitation do
  let(:organization) { create_organization }

  describe ".issue!" do
    it "returns the raw token and persists only its digest" do
      invitation, raw_token = described_class.issue!(organization: organization)

      expect(raw_token).to be_present
      expect(invitation.token_digest).to eq(Digest::SHA256.hexdigest(raw_token))
      expect(described_class.column_names).not_to include("token")
    end

    it "issues a distinct token each time" do
      _first, first_token = described_class.issue!(organization: organization)
      _second, second_token = described_class.issue!(organization: organization)

      expect(first_token).not_to eq(second_token)
    end

    it "downcases the invited email" do
      invitation, = described_class.issue!(organization: organization, email: "Invitee@Example.COM")

      expect(invitation.email).to eq("invitee@example.com")
    end

    it "defaults to the participant role and a two week expiry" do
      invitation, = described_class.issue!(organization: organization)

      expect(invitation.role).to eq("participant")
      expect(invitation.expires_at).to be_within(1.minute).of(14.days.from_now)
    end
  end

  describe ".find_by_raw_token" do
    it "finds the invitation for the matching raw token" do
      invitation, raw_token = described_class.issue!(organization: organization)

      expect(described_class.find_by_raw_token(raw_token)).to eq(invitation)
    end

    it "returns nil for an unknown token" do
      expect(described_class.find_by_raw_token("nope")).to be_nil
    end

    it "returns nil for a blank token rather than matching the digest of an empty string" do
      expect(described_class.find_by_raw_token(nil)).to be_nil
      expect(described_class.find_by_raw_token("")).to be_nil
    end
  end

  describe "#usable?" do
    it "is true for a pending, unexpired invitation" do
      invitation, = described_class.issue!(organization: organization)

      expect(invitation).to be_usable
    end

    it "is false once expired" do
      invitation, = described_class.issue!(organization: organization, expires_at: 1.minute.ago)

      expect(invitation).not_to be_usable
    end

    it "is false once accepted" do
      invitation, = described_class.issue!(organization: organization)
      invitation.accept!(create_user(email: "invitee@example.com"))

      expect(invitation).not_to be_usable
    end
  end

  describe ".pending" do
    it "excludes expired and accepted invitations" do
      pending_invitation, = described_class.issue!(organization: organization)
      described_class.issue!(organization: organization, expires_at: 1.day.ago)
      accepted, = described_class.issue!(organization: organization)
      accepted.accept!(create_user(email: "invitee@example.com"))

      expect(described_class.pending).to contain_exactly(pending_invitation)
    end
  end

  it "rejects an unknown role" do
    invitation, = described_class.issue!(organization: organization)
    invitation.role = "owner"

    expect(invitation).not_to be_valid
  end

  it "rejects a malformed email" do
    invitation, = described_class.issue!(organization: organization)
    invitation.email = "not-an-email"

    expect(invitation).not_to be_valid
  end
end
