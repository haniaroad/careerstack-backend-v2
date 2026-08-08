# frozen_string_literal: true

class AiReviewSerializer
  def self.call(review)
    new(review).as_json
  end

  def initialize(review)
    @review = review
  end

  def as_json
    {
      id: @review.id,
      task_id: @review.task_id,
      task_submission_id: @review.task_submission_id,
      status: @review.status,
      decision: @review.decision,
      feedback: @review.feedback,
      analysis_incomplete: @review.analysis_incomplete,
      unsupported_items: @review.unsupported_items,
      model: @review.model,
      prompt_version: @review.prompt_version,
      error_code: @review.error_code,
      error_message: @review.error_message,
      retryable: @review.failed? && !@review.counts_as_attempt,
      completed_at: @review.completed_at,
      created_at: @review.created_at
    }
  end
end
