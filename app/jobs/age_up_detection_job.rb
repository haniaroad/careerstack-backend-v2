# frozen_string_literal: true

# Daily sweep that promotes organization-derived minors who have reached 18 in
# their organization's timezone (D-13).
#
# Reaching adulthood grants the Personal workspace and the personal trial credit
# that were withheld while the user was a minor, but public identity stays off:
# the user is flagged for visibility review and must confirm explicitly before
# anything about them becomes public.
class AgeUpDetectionJob < ApplicationJob
  queue_as :default

  # A date of birth cannot make somebody an adult before this cutoff in any
  # timezone, so the scan is bounded rather than reading every minor.
  DATE_SLACK = 2.days

  def perform
    candidates.find_each do |user|
      promote(user) if adult_now?(user)
    end
  end

  private

  def candidates
    User.joins(:profile)
        .where(age_status: AgeStatusCalculator::MINOR, onboarding_path: "organization_invited")
        .where(profiles: { date_of_birth: ..cutoff_date })
  end

  def cutoff_date
    (Time.current + DATE_SLACK).to_date - AgeStatusCalculator::ADULT_AGE.years
  end

  def adult_now?(user)
    AgeStatusCalculator.call(
      date_of_birth: user.profile.date_of_birth,
      timezone: governing_timezone(user)
    ) == AgeStatusCalculator::ADULT
  end

  # The inviting organization governs the adult boundary; fall back to the
  # earliest membership when a user belongs to several.
  def governing_timezone(user)
    user.organization_memberships
        .includes(:organization)
        .order(:created_at)
        .first
        &.organization
        &.timezone || "UTC"
  end

  def promote(user)
    ActiveRecord::Base.transaction do
      user.update!(age_status: AgeStatusCalculator::ADULT)

      preference = user.age_visibility_preference || user.create_age_visibility_preference!
      preference.require_visibility_review!

      Workspaces::EnsurePersonal.call(user: user)
      Credits::GrantPersonalTrial.call(user: user)
    end

    Notifications::Hook.emit(
      event_key: "age_up_visibility_review",
      actor: nil,
      recipients: [ user ],
      source: user,
      payload: {}
    )
  end
end
