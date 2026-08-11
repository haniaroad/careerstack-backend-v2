# frozen_string_literal: true

module Tasks
  class ApplyReviewDecision
    def self.call(task:, review:)
      new(task: task, review: review).call
    end

    def initialize(task:, review:)
      @task = task
      @review = review
    end

    def call
      ActiveRecord::Base.transaction do
        @task.lock!
        case @review.decision
        when AiReview::DECISION_APPROVED
          @task.update!(status: Task::STATUS_APPROVED)
        when AiReview::DECISION_CORRECTIONS_REQUESTED
          @task.update!(status: Task::STATUS_CORRECTIONS_REQUESTED)
        else
          raise DomainError.new("Unknown review decision", code: "validation_error")
        end
      end

      if @review.decision == AiReview::DECISION_APPROVED
        Projects::Lifecycle::Evaluate.call(project: @task.project.reload)
      end

      @task.reload
    end
  end
end
