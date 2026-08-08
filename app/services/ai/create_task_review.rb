# frozen_string_literal: true

module Ai
  class CreateTaskReview
    PER_TASK_LIMIT = 10
    PER_USER_LIMIT = 30
    COOLDOWN_SECONDS = 60

    def self.call(task:, submission:, user:, auto: false)
      new(task: task, submission: submission, user: user, auto: auto).call
    end

    def initialize(task:, submission:, user:, auto:)
      @task = task
      @submission = submission
      @user = user
      @auto = auto
    end

    def call
      authorize!
      return nil if blocked_by_runtime_and_auto?

      enforce_runtime_controls!
      enforce_solo!
      enforce_concurrency!
      enforce_rate_limits!
      enforce_cooldown!

      review = AiReview.create!(
        task: @task,
        task_submission: @submission,
        user: @user,
        status: AiReview::STATUS_PENDING,
        content_fingerprint: @submission.content_fingerprint,
        prompt_version: Ai::Config.use_case("task_review")[:prompt_version],
        model: Ai::Config.use_case("task_review")[:model]
      )

      dispatch!(review)
      review
    rescue ActiveRecord::RecordNotUnique
      raise DomainError.new("A review is already in progress for this task", code: "ai_review_in_progress", status: :conflict)
    end

    private

    def authorize!
      raise DomainError.new("Only the assignee can request review", code: "forbidden", status: :forbidden) unless @task.assignee_id == @user.id
      raise DomainError.new("Submission does not belong to task", code: "validation_error") unless @submission.task_id == @task.id
    end

    def blocked_by_runtime_and_auto?
      @auto && (Ai::Config.nonessential_ai_stopped? || !Ai::Config.configured?)
    end

    def enforce_runtime_controls!
      if Ai::Config.nonessential_ai_stopped?
        raise DomainError.new("AI review is temporarily unavailable", code: "ai_unavailable", status: :service_unavailable)
      end

      unless Ai::Config.configured?
        raise DomainError.new("AI provider is not configured", code: "ai_not_configured", status: :service_unavailable)
      end
    end

    def enforce_solo!
      return if @task.project.solo?

      raise DomainError.new("AI review is only available for solo projects", code: "validation_error")
    end

    def enforce_concurrency!
      return unless @task.ai_reviews.active.exists?

      raise DomainError.new("A review is already in progress for this task", code: "ai_review_in_progress", status: :conflict)
    end

    def enforce_rate_limits!
      window = 24.hours.ago
      task_count = @task.ai_reviews.terminal_attempts.where("completed_at >= ?", window).count
      if task_count >= PER_TASK_LIMIT
        raise DomainError.new("AI review rate limit exceeded for this task", code: "ai_rate_limited", status: :too_many_requests)
      end

      user_count = AiReview.for_user(@user).terminal_attempts.where("completed_at >= ?", window).count
      if user_count >= PER_USER_LIMIT
        raise DomainError.new("AI review rate limit exceeded", code: "ai_rate_limited", status: :too_many_requests)
      end
    end

    def enforce_cooldown!
      last = @task.ai_reviews.where(content_fingerprint: @submission.content_fingerprint).order(created_at: :desc).first
      return if last.nil?
      return if last.created_at < COOLDOWN_SECONDS.seconds.ago

      raise DomainError.new("Please wait before requesting another review of the same submission", code: "ai_review_cooldown", status: :too_many_requests)
    end

    def dispatch!(review)
      if ENV.fetch("AI_INLINE_JOBS", "false") == "true" || Rails.env.test?
        Ai::RunTaskReview.call(review: review)
      else
        Ai::TaskReviewJob.perform_later(review.id)
      end
    end
  end
end
