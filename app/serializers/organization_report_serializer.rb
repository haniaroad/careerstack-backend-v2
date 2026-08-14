# frozen_string_literal: true

class OrganizationReportSerializer
  def self.call(report)
    {
      id: report.id,
      organization_id: report.organization_id,
      title: report.title,
      program_id: report.program_id,
      program_name: report.program&.name,
      period_starts_on: report.period_starts_on,
      period_ends_on: report.period_ends_on,
      period_label: report.period_label,
      format: report.format,
      aggregate_only: report.aggregate_only,
      includes_minor_names: report.includes_minor_names,
      status: report.status,
      generated_at: report.generated_at,
      methodology_note: report.methodology_note,
      error_code: report.error_code
    }
  end
end
