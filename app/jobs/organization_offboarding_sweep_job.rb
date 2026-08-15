# frozen_string_literal: true

class OrganizationOffboardingSweepJob < ApplicationJob
  queue_as :default

  def perform
    today = Time.find_zone!("UTC").today

    Organization.where(workspace_status: Organization::WORKSPACE_OFFBOARDING)
                .where.not(offboarding_ends_on: nil)
                .find_each do |organization|
      days_remaining = (organization.offboarding_ends_on - today).to_i
      Organizations::EmitOffboardingNotice.call(organization: organization, days_remaining: days_remaining)
      next if days_remaining.positive?

      Organizations::Disable.call(organization: organization)
    end
  end
end
