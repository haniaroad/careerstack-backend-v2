# frozen_string_literal: true

class PeerReview < ApplicationRecord
  STATUS_AVAILABLE = "available"
  STATUS_PENDING = "pending"
  STATUS_COMPLETED = "completed"
  STATUSES = [ STATUS_AVAILABLE, STATUS_PENDING, STATUS_COMPLETED ].freeze
  RATINGS = (1..5).to_a.freeze
  ANONYMIZED_LABEL = "Verified project teammate"

  belongs_to :project
  belongs_to :reviewer, class_name: "User"
  belongs_to :reviewee, class_name: "User"
  has_many :reports, class_name: "PeerReviewReport", dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :reviewer_id, uniqueness: { scope: [ :project_id, :reviewee_id ] }
  validate :reviewer_is_not_reviewee
  validate :completed_fields, if: :completed?
  validate :available_fields, unless: :completed?

  scope :available, -> { where(status: STATUS_AVAILABLE) }
  scope :completed, -> { where(status: STATUS_COMPLETED) }
  scope :visible, -> { where(hidden_at: nil) }
  scope :received_by, ->(user) { completed.visible.where(reviewee_id: user.id) }
  scope :authored_by, ->(user) { where(reviewer_id: user.id) }
  scope :in_workspace, ->(workspace) { joins(:project).where(projects: { workspace_id: workspace.id }) }

  def available?
    status == STATUS_AVAILABLE
  end

  def completed?
    status == STATUS_COMPLETED
  end

  def hidden?
    hidden_at.present?
  end

  def anonymized?
    reviewer_minor? || reviewee_minor?
  end

  def reviewer_display_name
    return ANONYMIZED_LABEL if anonymized?

    reviewer.profile&.display_name.presence || ANONYMIZED_LABEL
  end

  def reviewer_minor?
    reviewer.age_status == AgeStatusCalculator::MINOR
  end

  def reviewee_minor?
    reviewee.age_status == AgeStatusCalculator::MINOR
  end

  private

  def reviewer_is_not_reviewee
    return if reviewer_id.blank? || reviewee_id.blank?
    return if reviewer_id != reviewee_id

    errors.add(:reviewee_id, "cannot be the reviewer")
  end

  def completed_fields
    errors.add(:rating, "is required") unless RATINGS.include?(rating)
    errors.add(:comment, "is required") if comment.to_s.strip.blank?
  end

  def available_fields
    errors.add(:rating, "must be blank until submitted") if rating.present?
    errors.add(:comment, "must be blank until submitted") if comment.present?
  end
end
