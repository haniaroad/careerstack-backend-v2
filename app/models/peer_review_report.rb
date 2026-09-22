# frozen_string_literal: true

class PeerReviewReport < ApplicationRecord
  STATUS_OPEN = "open"
  STATUS_CLOSED = "closed"
  STATUSES = [ STATUS_OPEN, STATUS_CLOSED ].freeze

  REPORT_TYPES = %w[inaccurate inappropriate harassment other].freeze
  REASON_CATEGORIES = %w[
    wrong_decision
    missing_context
    unsafe_or_biased
    unclear_feedback
    harassment
    other
  ].freeze

  belongs_to :peer_review
  belongs_to :reporter, class_name: "User"

  validates :report_type, inclusion: { in: REPORT_TYPES }
  validates :reason_category, inclusion: { in: REASON_CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :reporter_id, uniqueness: { scope: :peer_review_id, conditions: -> { where(status: STATUS_OPEN) } }
end
