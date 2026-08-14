# frozen_string_literal: true

class OrganizationOffboardingSweepJob < ApplicationJob
  queue_as :default

  def perform
    Organization.where(workspace_status: Organization::WORKSPACE_OFFBOARDING)
                .where(offboarding_ends_on: ..Time.find_zone!("UTC").today)
                .find_each do |organization|
      Organizations::Disable.call(organization: organization)
    end
  end
end
