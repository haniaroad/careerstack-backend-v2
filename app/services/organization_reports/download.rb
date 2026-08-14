# frozen_string_literal: true

module OrganizationReports
  class Download
    EXPIRY = 15.minutes
    MINOR_CONFIRM_CODE = "minor_names_confirmation_required"

    def self.call(report:, actor:, confirm_minor_names:, host:)
      new(report: report, actor: actor, confirm_minor_names: confirm_minor_names, host: host).call
    end

    def initialize(report:, actor:, confirm_minor_names:, host:)
      @report = report
      @actor = actor
      @confirm_minor_names = confirm_minor_names
      @host = host
    end

    def call
      Organizations::Access.require_exportable!(@report.organization)
      raise Error.new("Report is not ready to download", code: "report_not_ready") unless @report.ready?
      raise Error.new("Report file is missing", code: "report_not_ready") unless @report.file.attached?

      if @report.includes_minor_names && !@confirm_minor_names
        raise Error.new(
          "This report includes minor names. Confirm before download.",
          code: MINOR_CONFIRM_CODE
        )
      end

      OrganizationReports::Audit.record!(
        report: @report,
        actor: @actor,
        action: OrganizationReportAudit::ACTION_DOWNLOAD
      )

      expires_at = EXPIRY.from_now
      { url: blob_url, expires_at: expires_at }
    end

    private

    def blob_url
      Rails.application.routes.url_helpers.rails_blob_url(
        @report.file,
        expires_in: EXPIRY,
        disposition: "attachment",
        host: @host.presence || "www.example.com"
      )
    end
  end
end
