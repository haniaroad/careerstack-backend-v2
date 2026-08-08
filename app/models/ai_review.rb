# frozen_string_literal: true

class AiReview < ApplicationRecord
  STATUS_PENDING = "pending"
  STATUS_RUNNING = "running"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  STATUSES = [ STATUS_PENDING, STATUS_RUNNING, STATUS_SUCCEEDED, STATUS_FAILED ].freeze

  DECISION_APPROVED = "approved"
  DECISION_CORRECTIONS_REQUESTED = "corrections_requested"
  DECISIONS = [ DECISION_APPROVED, DECISION_CORRECTIONS_REQUESTED ].freeze

  ACTIVE_STATUSES = [ STATUS_PENDING, STATUS_RUNNING ].freeze

  belongs_to :task
  belongs_to :task_submission
  belongs_to :user
  has_many :reports, class_name: "AiReviewReport", dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :decision, inclusion: { in: DECISIONS }, allow_nil: true
  validates :content_fingerprint, presence: true

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :terminal_attempts, -> { where(counts_as_attempt: true) }
  scope :for_user, ->(user) { where(user_id: user.id) }

  def pending?
    status == STATUS_PENDING
  end

  def running?
    status == STATUS_RUNNING
  end

  def succeeded?
    status == STATUS_SUCCEEDED
  end

  def failed?
    status == STATUS_FAILED
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def owner?(user)
    user_id == user.id
  end
end
