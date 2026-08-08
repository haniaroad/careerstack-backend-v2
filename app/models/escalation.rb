# frozen_string_literal: true

class Escalation < ApplicationRecord
  TARGET_STAFF = "staff"
  TARGET_ORGANIZATION = "organization"
  TARGETS = [ TARGET_STAFF, TARGET_ORGANIZATION ].freeze

  STATUS_OPEN = "open"
  STATUS_RESOLVED = "resolved"
  STATUSES = [ STATUS_OPEN, STATUS_RESOLVED ].freeze

  REASON_APPLICATION_OVERDUE = "application_overdue"
  REASON_TASK_REVIEW_OVERDUE = "task_review_overdue"
  REASON_NO_TASKS_CREATED = "no_tasks_created"
  REASONS = [
    REASON_APPLICATION_OVERDUE,
    REASON_TASK_REVIEW_OVERDUE,
    REASON_NO_TASKS_CREATED
  ].freeze

  belongs_to :workspace
  belongs_to :project
  belongs_to :organization, optional: true

  validates :target, inclusion: { in: TARGETS }
  validates :reason, inclusion: { in: REASONS }
  validates :status, inclusion: { in: STATUSES }
  validates :subject_type, :subject_id, :idempotency_key, presence: true
end
