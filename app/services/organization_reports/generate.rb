# frozen_string_literal: true

module OrganizationReports
  class Generate
    def self.call(report:)
      new(report: report).call
    end

    def initialize(report:)
      @report = report
    end

    def call
      raise Error.new("Ready snapshots cannot be regenerated", code: "report_immutable") if @report.ready?

      freezer = FreezeMetrics.new(report: @report)
      metrics = freezer.call
      includes_minors = freezer.includes_minor_names?(metrics)
      bytes = if @report.format == OrganizationReport::FORMAT_PDF
        RenderPdf.call(report: @report, metrics: metrics)
      else
        RenderCsv.call(report: @report, metrics: metrics)
      end

      filename = "#{@report.title.parameterize.presence || "organization-report"}.#{@report.format}"
      content_type = @report.format == OrganizationReport::FORMAT_PDF ? "application/pdf" : "text/csv"

      @report.file.attach(io: StringIO.new(bytes), filename: filename, content_type: content_type)
      @report.update!(
        status: OrganizationReport::STATUS_READY,
        metrics_json: metrics,
        includes_minor_names: includes_minors,
        generated_at: Time.current,
        error_code: nil,
        methodology_note: OrganizationReport::METHODOLOGY_NOTE
      )
      OrganizationReports::Audit.record!(
        report: @report,
        actor: @report.requested_by,
        action: OrganizationReportAudit::ACTION_GENERATE
      )
      @report
    rescue OrganizationReports::Error
      raise
    rescue StandardError => error
      @report.update!(status: OrganizationReport::STATUS_FAILED, error_code: "generate_failed")
      Rails.logger.error({
        event: "organization_report_generate_failed",
        report_id: @report.id,
        error: error.class.name,
        message: error.message
      })
      raise Error.new("Report generation failed", code: "generate_failed")
    end
  end
end
