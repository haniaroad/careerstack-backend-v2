# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgeUpDetectionJob do
  let(:organization) { create_organization(name: "Bridge Academy", timezone: "America/New_York") }

  def create_invited_minor(email:, date_of_birth:)
    user = create_user(email: email, status: User::ACTIVE)
    user.create_profile!(minimum_profile_attributes(date_of_birth: date_of_birth))
    user.update!(onboarding_path: "organization_invited", age_status: AgeStatusCalculator::MINOR)
    user.create_age_visibility_preference!
    create_membership(organization: organization, user: user)
    user.reload
  end

  it "promotes a minor whose 18th birthday has arrived in the organization timezone" do
    local_today = Time.current.in_time_zone(organization.timezone).to_date
    user = create_invited_minor(email: "grown@example.com", date_of_birth: local_today - 18.years)

    described_class.perform_now

    expect(user.reload.age_status).to eq("adult")
  end

  it "grants the withheld Personal workspace and personal trial credit" do
    local_today = Time.current.in_time_zone(organization.timezone).to_date
    user = create_invited_minor(email: "grown@example.com", date_of_birth: local_today - 18.years)

    described_class.perform_now

    user.reload
    expect(user.personal_workspace).to be_present
    expect(user.personal_trial_granted).to be(true)
    expect(CreditLedgerEntry.where(owner: user, reason: "personal_trial").sum(:amount)).to eq(1)
  end

  it "requires a visibility review and keeps public identity off until confirmed" do
    local_today = Time.current.in_time_zone(organization.timezone).to_date
    user = create_invited_minor(email: "grown@example.com", date_of_birth: local_today - 18.years)

    described_class.perform_now

    preference = user.age_visibility_preference.reload
    expect(preference.visibility_review_required).to be(true)
    expect(preference.public_identity_confirmed).to be(false)
    expect(user.reload.public_identity_visible?).to be(false)
  end

  it "leaves a minor whose birthday has not arrived untouched" do
    user = create_invited_minor(email: "still-minor@example.com", date_of_birth: 15.years.ago.to_date)

    described_class.perform_now

    user.reload
    expect(user.age_status).to eq("minor")
    expect(user.personal_workspace).to be_nil
    expect(CreditLedgerEntry.where(owner: user)).to be_empty
  end

  it "does not promote a minor one day short of 18 in the organization timezone" do
    local_today = Time.current.in_time_zone(organization.timezone).to_date
    user = create_invited_minor(email: "tomorrow@example.com", date_of_birth: local_today - 18.years + 1.day)

    described_class.perform_now

    expect(user.reload.age_status).to eq("minor")
  end

  it "leaves unknown-age users alone because they have no date of birth" do
    user = create_user(email: "unknown@example.com", status: User::ACTIVE)
    user.create_profile!(minimum_profile_attributes)
    user.update!(onboarding_path: "organization_invited", age_status: AgeStatusCalculator::UNKNOWN)
    create_membership(organization: organization, user: user)

    described_class.perform_now

    expect(user.reload.age_status).to eq("unknown")
    expect(user.personal_workspace).to be_nil
  end

  it "is idempotent across repeated runs" do
    local_today = Time.current.in_time_zone(organization.timezone).to_date
    user = create_invited_minor(email: "grown@example.com", date_of_birth: local_today - 18.years)

    described_class.perform_now
    described_class.perform_now

    expect(CreditLedgerEntry.where(owner: user, reason: "personal_trial").count).to eq(1)
    expect(Workspace.where(owner_user: user).count).to eq(1)
  end

  it "ignores independent users, who never store a date of birth" do
    user = create_onboarded_adult(email: "independent@example.com")
    user.update!(age_status: AgeStatusCalculator::MINOR)

    expect { described_class.perform_now }.not_to change { user.reload.age_status }
  end
end
