# frozen_string_literal: true

module OrganizationReports
  class EnqueueGenerate
    def self.call(report:, actor:)
      new(report: report, actor: actor).call
    end

    def initialize(report:, actor:)
      @report = report
      @actor = actor
    end

    def call
      Organizations::Access.require_exportable!(@report.organization)
      raise Error.new("Ready snapshots cannot be regenerated", code: "report_immutable") if @report.ready?
      unless @report.draft? || @report.failed?
        raise Error.new("This report cannot be generated in its current state")
      end

      generating = @report.organization.organization_reports.generating.where.not(id: @report.id)
      if generating.exists?
        raise Error.new("Another report is already generating for this organization", code: "report_busy")
      end

      @report.update!(status: OrganizationReport::STATUS_GENERATING, error_code: nil)

      if inline?
        Generate.call(report: @report.reload)
      else
        OrganizationReports::GenerateJob.perform_later(@report.id)
      end

      @report.reload
    end

    private

    def inline?
      ENV["REPORTS_INLINE_JOBS"].to_s == "true" || Rails.env.test?
    end
  end
end
