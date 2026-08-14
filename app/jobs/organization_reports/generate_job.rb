# frozen_string_literal: true

module OrganizationReports
  class GenerateJob < ApplicationJob
    queue_as :reports

    def perform(report_id)
      report = OrganizationReport.find_by(id: report_id)
      return if report.nil? || report.ready?

      Generate.call(report: report)
    rescue OrganizationReports::Error
      nil
    end
  end
end
