# frozen_string_literal: true

class TaskSerializer
  def self.call(task, include_detail: false, viewer: nil)
    new(task, include_detail: include_detail, viewer: viewer).as_json
  end

  def initialize(task, include_detail: false, viewer: nil)
    @task = task
    @include_detail = include_detail
    @viewer = viewer
  end

  def as_json
    payload = {
      id: @task.id,
      project_id: @task.project_id,
      project_title: @task.project.title,
      project_mode: @task.project.mode,
      project_status: @task.project.status,
      project_phase: @task.project.phase,
      project_creator_id: @task.project.creator_id,
      assignee_id: @task.assignee_id,
      title: @task.title,
      acceptance_criteria: @task.acceptance_criteria,
      submission_expectations: @task.submission_expectations,
      due_on: @task.due_on,
      reference_video_url: @task.reference_video_url,
      status: @task.status,
      position: @task.position,
      first_submitted_at: @task.first_submitted_at,
      on_time: @task.on_time,
      review_overdue_at: @task.review_overdue_at,
      creator_review_decision: @task.creator_review_decision,
      creator_review_feedback: @task.creator_review_feedback,
      creator_reviewed_by_id: @task.creator_reviewed_by_id,
      creator_reviewed_at: @task.creator_reviewed_at,
      created_at: @task.created_at,
      updated_at: @task.updated_at,
      viewer_can_claim: viewer_can_claim?
    }

    if @include_detail
      payload[:submissions] = @task.submissions.order(:attempt_number).map { |s| TaskSubmissionSerializer.call(s) }
      latest_review = @task.ai_reviews.order(created_at: :desc).first
      payload[:latest_review] = latest_review ? AiReviewSerializer.call(latest_review) : nil
    end

    payload
  end

  private

  def viewer_can_claim?
    return false if @viewer.nil?

    project = @task.project
    return false unless project.team?
    return false unless @task.pending?
    return false if @task.assignee_id.present?
    return false if project.creator_id == @viewer.id

    project.memberships.active.exists?(user_id: @viewer.id)
  end
end
