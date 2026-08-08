# frozen_string_literal: true

class AiReviewReportSerializer
  def self.call(report)
    new(report).as_json
  end

  def initialize(report)
    @report = report
  end

  def as_json
    {
      id: @report.id,
      ai_review_id: @report.ai_review_id,
      report_type: @report.report_type,
      reason_category: @report.reason_category,
      details: @report.details,
      status: @report.status,
      created_at: @report.created_at
    }
  end
end
