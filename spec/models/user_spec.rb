# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe "validations" do
    it "requires a unique email" do
      create_user(email: "taken@example.com")
      duplicate = User.new(firebase_uid: "uid-other", email: "taken@example.com")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end

    it "requires a unique firebase uid" do
      existing = create_user(email: "first@example.com")
      duplicate = User.new(firebase_uid: existing.firebase_uid, email: "second@example.com")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:firebase_uid]).to be_present
    end

    it "rejects a status outside the allowed set" do
      user = User.new(firebase_uid: "uid-x", email: "x@example.com", status: "banished")

      expect(user).not_to be_valid
      expect(user.errors[:status]).to be_present
    end

    it "rejects an age status outside the allowed set" do
      user = User.new(firebase_uid: "uid-x", email: "x@example.com", age_status: "teenager")

      expect(user).not_to be_valid
    end

    it "allows a nil age status before onboarding" do
      expect(create_user(email: "pending@example.com").age_status).to be_nil
    end
  end

  describe "#privacy_restricted?" do
    it "is false for adults" do
      user = create_user(email: "a@example.com", age_status: AgeStatusCalculator::ADULT)

      expect(user).not_to be_privacy_restricted
    end

    it "is true for minors, unknown age, and users who have not onboarded" do
      [ AgeStatusCalculator::MINOR, AgeStatusCalculator::UNKNOWN, nil ].each_with_index do |age_status, index|
        user = create_user(email: "restricted-#{index}@example.com", age_status: age_status)

        expect(user).to be_privacy_restricted
      end
    end
  end

  describe "#public_identity_visible?" do
    it "is true for an independent adult without any review" do
      expect(create_onboarded_adult(email: "independent@example.com").public_identity_visible?).to be(true)
    end

    it "is false for an org-derived adult who has not confirmed" do
      user = create_user(email: "orgadult@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::ADULT)
      user.update!(onboarding_path: "organization_invited")
      user.create_age_visibility_preference!(visibility_review_required: true)

      expect(user.public_identity_visible?).to be(false)
    end

    it "is true once an org-derived adult confirms" do
      user = create_user(email: "orgadult@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::ADULT)
      user.update!(onboarding_path: "organization_invited")
      user.create_age_visibility_preference!.confirm_public_identity!

      expect(user.reload.public_identity_visible?).to be(true)
    end

    it "is false for a minor regardless of preferences" do
      user = create_user(email: "minor@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::MINOR)
      user.create_age_visibility_preference!(public_identity_confirmed: true)

      expect(user.public_identity_visible?).to be(false)
    end
  end

  describe "#member_of_workspace?" do
    let(:user) { create_onboarded_adult(email: "member@example.com") }

    it "is true for the user's own Personal workspace" do
      expect(user.member_of_workspace?(user.personal_workspace)).to be(true)
    end

    it "is false for another user's Personal workspace" do
      other = create_onboarded_adult(email: "other@example.com")

      expect(user.member_of_workspace?(other.personal_workspace)).to be(false)
    end

    it "is true for an organization the user belongs to" do
      organization = create_organization
      create_membership(organization: organization, user: user)

      expect(user.member_of_workspace?(organization.workspace)).to be(true)
    end

    it "is false for an organization the user does not belong to" do
      expect(user.member_of_workspace?(create_organization.workspace)).to be(false)
    end

    it "is false for nil" do
      expect(user.member_of_workspace?(nil)).to be(false)
    end
  end

  describe "#default_workspace" do
    it "prefers Personal over an organization membership" do
      user = create_onboarded_adult(email: "member@example.com")
      create_membership(organization: create_organization, user: user)

      expect(user.default_workspace).to eq(user.personal_workspace)
    end

    it "falls back to an organization workspace without Personal" do
      minor = create_user(email: "minor@example.com", status: User::ACTIVE, age_status: AgeStatusCalculator::MINOR)
      organization = create_organization
      create_membership(organization: organization, user: minor)

      expect(minor.default_workspace).to eq(organization.workspace)
    end

    it "is nil when the user has no workspaces yet" do
      expect(create_user(email: "pending@example.com").default_workspace).to be_nil
    end
  end

  describe "#can_access_org_admin_for?" do
    let(:user) { create_onboarded_adult(email: "member@example.com") }
    let(:organization) { create_organization }

    it "is true for an admin" do
      create_membership(organization: organization, user: user, role: OrganizationMembership::ADMIN)

      expect(user.can_access_org_admin_for?(organization.workspace)).to be(true)
    end

    it "is true for a manager" do
      create_membership(organization: organization, user: user, role: OrganizationMembership::MANAGER)

      expect(user.can_access_org_admin_for?(organization.workspace)).to be(true)
    end

    it "is false for a participant" do
      create_membership(organization: organization, user: user)

      expect(user.can_access_org_admin_for?(organization.workspace)).to be(false)
    end

    it "is false for a Personal workspace" do
      expect(user.can_access_org_admin_for?(user.personal_workspace)).to be(false)
    end
  end
end
