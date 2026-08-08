# frozen_string_literal: true

module Ai
  class CreateReviewReport
    def self.call(review:, user:, report_type:, reason_category:, details: nil)
      new(
        review: review,
        user: user,
        report_type: report_type,
        reason_category: reason_category,
        details: details
      ).call
    end

    def initialize(review:, user:, report_type:, reason_category:, details:)
      @review = review
      @user = user
      @report_type = report_type.to_s
      @reason_category = reason_category.to_s
      @details = details.to_s.presence
    end

    def call
      raise DomainError.new("Only the review owner can report feedback", code: "forbidden", status: :forbidden) unless @review.owner?(@user)
      raise DomainError.new("Only succeeded reviews can be reported", code: "validation_error") unless @review.succeeded?

      unless AiReviewReport::REPORT_TYPES.include?(@report_type)
        raise DomainError.new("Invalid report type", code: "validation_error")
      end
      unless AiReviewReport::REASON_CATEGORIES.include?(@reason_category)
        raise DomainError.new("Invalid reason category", code: "validation_error")
      end

      report = AiReviewReport.create!(
        ai_review: @review,
        reporter: @user,
        report_type: @report_type,
        reason_category: @reason_category,
        details: @details,
        status: AiReviewReport::STATUS_OPEN
      )

      # Intentionally does not mutate task status or review decision.
      report
    end
  end
end
