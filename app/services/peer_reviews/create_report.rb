# frozen_string_literal: true

module PeerReviews
  class CreateReport
    def self.call(review:, actor:, report_type:, reason_category:, details: nil)
      new(
        review: review,
        actor: actor,
        report_type: report_type,
        reason_category: reason_category,
        details: details
      ).call
    end

    def initialize(review:, actor:, report_type:, reason_category:, details:)
      @review = review
      @actor = actor
      @report_type = report_type.to_s
      @reason_category = reason_category.to_s
      @details = details.to_s.presence
    end

    def call
      raise DomainError.new("Review not found", code: "not_found", status: :not_found) unless readable?
      raise DomainError.new("You cannot report your own review", code: "forbidden", status: :forbidden) if @review.reviewer_id == @actor.id
      raise DomainError.new("Invalid report type", code: "validation_error") unless PeerReviewReport::REPORT_TYPES.include?(@report_type)
      raise DomainError.new("Invalid reason category", code: "validation_error") unless PeerReviewReport::REASON_CATEGORIES.include?(@reason_category)

      PeerReviewReport.create!(
        peer_review: @review,
        reporter: @actor,
        report_type: @report_type,
        reason_category: @reason_category,
        details: @details,
        status: PeerReviewReport::STATUS_OPEN
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      raise DomainError.new("You already reported this review", code: "validation_error")
    end

    private

    def readable?
      return false unless @review.completed? && !@review.hidden?
      return true if @review.reviewee_id == @actor.id

      Profiles::Visibility.public_adult?(@review.reviewee)
    end
  end
end
