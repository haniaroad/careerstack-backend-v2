# frozen_string_literal: true

class ContributionEvent < ApplicationRecord
  KIND_TASK_SUBMITTED = "task_submitted"
  KIND_TASK_APPROVED = "task_approved"
  KIND_ARTIFACT_UPLOADED = "artifact_uploaded"
  KIND_PEER_REVIEW_SUBMITTED = "peer_review_submitted"
  KIND_PROJECT_COMPLETED = "project_completed"
  KINDS = [
    KIND_TASK_SUBMITTED,
    KIND_TASK_APPROVED,
    KIND_ARTIFACT_UPLOADED,
    KIND_PEER_REVIEW_SUBMITTED,
    KIND_PROJECT_COMPLETED
  ].freeze

  WORKSPACE_PERSONAL = "personal"
  WORKSPACE_ORGANIZATION = "organization"
  WORKSPACE_KINDS = [ WORKSPACE_PERSONAL, WORKSPACE_ORGANIZATION ].freeze

  belongs_to :user

  validates :kind, inclusion: { in: KINDS }
  validates :workspace_kind, inclusion: { in: WORKSPACE_KINDS }
  validates :subject_type, :subject_id, :occurred_at, :idempotency_key, presence: true
  validates :idempotency_key, uniqueness: true
end
