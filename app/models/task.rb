# frozen_string_literal: true

class Task < ApplicationRecord
  STATUS_PENDING = "pending"
  STATUS_SUBMITTED = "submitted"
  STATUS_CORRECTIONS_REQUESTED = "corrections_requested"
  STATUS_APPROVED = "approved"
  STATUS_INCOMPLETE = "incomplete"
  STATUSES = [
    STATUS_PENDING,
    STATUS_SUBMITTED,
    STATUS_CORRECTIONS_REQUESTED,
    STATUS_APPROVED,
    STATUS_INCOMPLETE
  ].freeze

  SUBMITTABLE_STATUSES = [ STATUS_PENDING, STATUS_CORRECTIONS_REQUESTED ].freeze

  DECISION_APPROVED = "approved"
  DECISION_CORRECTIONS_REQUESTED = "corrections_requested"
  CREATOR_DECISIONS = [ DECISION_APPROVED, DECISION_CORRECTIONS_REQUESTED ].freeze

  belongs_to :project
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :creator_reviewed_by, class_name: "User", optional: true
  has_many :submissions, class_name: "TaskSubmission", dependent: :destroy
  has_many :ai_reviews, dependent: :destroy

  validates :title, presence: true, length: { maximum: 200 }
  validates :status, inclusion: { in: STATUSES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :creator_review_decision, inclusion: { in: CREATOR_DECISIONS }, allow_nil: true

  scope :for_assignee, ->(user) { where(assignee_id: user.id) }
  scope :in_workspace, ->(workspace) {
    joins(:project).where(projects: { workspace_id: workspace.id })
  }

  def pending?
    status == STATUS_PENDING
  end

  def submitted?
    status == STATUS_SUBMITTED
  end

  def corrections_requested?
    status == STATUS_CORRECTIONS_REQUESTED
  end

  def approved?
    status == STATUS_APPROVED
  end

  def incomplete?
    status == STATUS_INCOMPLETE
  end

  def submittable?
    SUBMITTABLE_STATUSES.include?(status)
  end
end
