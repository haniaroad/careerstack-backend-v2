# frozen_string_literal: true

module OrganizationReports
  class Audit
    def self.record!(report:, actor:, action:)
      OrganizationReportAudit.create!(
        organization: report.organization,
        organization_report: report,
        actor: actor,
        action: action,
        format: report.format,
        aggregate_only: report.aggregate_only,
        includes_minor_names: report.includes_minor_names,
        occurred_at: Time.current
      )
    end
  end
end
