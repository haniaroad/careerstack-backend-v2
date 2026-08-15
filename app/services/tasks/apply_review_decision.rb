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
        Profiles::RecordContribution.call(
          user: @task.assignee,
          kind: ContributionEvent::KIND_TASK_APPROVED,
          subject: @task,
          project: @task.project
        )
        Projects::Lifecycle::Evaluate.call(project: @task.project.reload)
        Notifications::Hook.emit(
          event_key: "task_approved",
          actor: nil,
          recipients: [ @task.assignee ],
          source: @review,
          project: @task.project,
          payload: Notifications::Hook.task_payload(@task)
        )
      elsif @review.decision == AiReview::DECISION_CORRECTIONS_REQUESTED
        Notifications::Hook.emit(
          event_key: "corrections_requested",
          actor: nil,
          recipients: [ @task.assignee ],
          source: @review,
          project: @task.project,
          payload: Notifications::Hook.task_payload(@task)
        )
      end

      @task.reload
    end
  end
end
