# frozen_string_literal: true

module OrganizationReports
  # A generating snapshot with no progress must not lock the organization.
  class ExpireStaleGenerations
    STALE_AFTER = 2.minutes

    def self.call(organization:)
      new(organization: organization).call
    end

    def initialize(organization:)
      @organization = organization
    end

    def call
      @organization.organization_reports.generating.where(updated_at: ..STALE_AFTER.ago).find_each do |report|
        report.update!(
          status: OrganizationReport::STATUS_FAILED,
          error_code: "generate_timeout"
        )
      end
    end
  end
end
