# frozen_string_literal: true

module Tasks
  class CreatorReview
    CORRECTIONS_LEAD_TIME = 48.hours
    FEEDBACK_MAX = 5000

    def self.call(task:, actor:, decision:, feedback: nil)
      new(task: task, actor: actor, decision: decision, feedback: feedback).call
    end

    def initialize(task:, actor:, decision:, feedback:)
      @task = task
      @actor = actor
      @decision = decision.to_s
      @feedback = feedback.to_s.strip.presence
    end

    def call
      project = @task.project
      authorize!(project)
      Projects::Lifecycle::ActionGate.assert!(project: project, action: :review_decide)
      validate_state!(project)

      ActiveRecord::Base.transaction do
        @task.lock!
        project = @task.project.reload
        Projects::Lifecycle::ActionGate.assert!(project: project, action: :review_decide)
        validate_state!(project)

        case @decision
        when Task::DECISION_APPROVED
          apply_approved!
        when Task::DECISION_CORRECTIONS_REQUESTED
          apply_corrections!(project)
        else
          raise DomainError.new("decision must be approved or corrections_requested", code: "validation_error")
        end
      end

      if @decision == Task::DECISION_APPROVED
        Profiles::RecordContribution.call(
          user: @task.assignee,
          kind: ContributionEvent::KIND_TASK_APPROVED,
          subject: @task,
          project: @task.project
        )
        Projects::Lifecycle::Evaluate.call(project: @task.project.reload)
      end

      @task.reload
    end

    private

    def authorize!(project)
      unless project.creator_id == @actor.id
        raise DomainError.new("Only the project creator can review team submissions", code: "forbidden", status: :forbidden)
      end
    end

    def validate_state!(project)
      unless project.mode == Project::MODE_TEAM
        raise DomainError.new("Creator review is only available for team projects", code: "validation_error")
      end
      unless project.active?
        raise DomainError.new("Project is not active", code: "validation_error")
      end
      unless @task.status == Task::STATUS_SUBMITTED
        raise DomainError.new("Only submitted tasks can be reviewed", code: "validation_error")
      end
    end

    def apply_approved!
      @task.update!(
        status: Task::STATUS_APPROVED,
        creator_review_decision: Task::DECISION_APPROVED,
        creator_review_feedback: @feedback,
        creator_reviewed_by: @actor,
        creator_reviewed_at: Time.current,
        review_overdue_at: nil
      )
    end

    def apply_corrections!(project)
      if @feedback.blank?
        raise DomainError.new("Feedback is required when requesting corrections", code: "validation_error")
      end
      if @feedback.length > FEEDBACK_MAX
        raise DomainError.new("Feedback is too long", code: "validation_error")
      end
      enforce_corrections_window!(project)

      @task.update!(
        status: Task::STATUS_CORRECTIONS_REQUESTED,
        creator_review_decision: Task::DECISION_CORRECTIONS_REQUESTED,
        creator_review_feedback: @feedback,
        creator_reviewed_by: @actor,
        creator_reviewed_at: Time.current,
        review_overdue_at: nil
      )
    end

    def enforce_corrections_window!(project)
      final_expiration = project.final_expires_at
      return if final_expiration.blank?

      remaining = final_expiration - Time.current
      return if remaining >= CORRECTIONS_LEAD_TIME

      raise DomainError.new(
        "Corrections can only be requested when at least 48 hours remain before final expiration",
        code: "corrections_window_closed"
      )
    end
  end
end
