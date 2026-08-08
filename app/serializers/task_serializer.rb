# frozen_string_literal: true

class TaskSerializer
  def self.call(task, include_detail: false)
    new(task, include_detail: include_detail).as_json
  end

  def initialize(task, include_detail: false)
    @task = task
    @include_detail = include_detail
  end

  def as_json
    payload = {
      id: @task.id,
      project_id: @task.project_id,
      project_title: @task.project.title,
      assignee_id: @task.assignee_id,
      title: @task.title,
      acceptance_criteria: @task.acceptance_criteria,
      submission_expectations: @task.submission_expectations,
      due_on: @task.due_on,
      status: @task.status,
      position: @task.position,
      first_submitted_at: @task.first_submitted_at,
      on_time: @task.on_time,
      created_at: @task.created_at,
      updated_at: @task.updated_at
    }

    if @include_detail
      payload[:submissions] = @task.submissions.order(:attempt_number).map { |s| TaskSubmissionSerializer.call(s) }
      latest_review = @task.ai_reviews.order(created_at: :desc).first
      payload[:latest_review] = latest_review ? AiReviewSerializer.call(latest_review) : nil
    end

    payload
  end
end
