# frozen_string_literal: true

class ProjectMessageReport < ApplicationRecord
  STATUS_OPEN = "open"
  STATUS_CLOSED = "closed"
  STATUSES = [ STATUS_OPEN, STATUS_CLOSED ].freeze

  REPORT_TYPES = %w[inappropriate harassment spam other].freeze
  REASON_CATEGORIES = %w[
    harassment
    unsafe_or_biased
    spam
    off_topic
    other
  ].freeze

  belongs_to :project_message
  belongs_to :reporter, class_name: "User"

  validates :report_type, inclusion: { in: REPORT_TYPES }
  validates :reason_category, inclusion: { in: REASON_CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :reporter_id, uniqueness: { scope: :project_message_id, conditions: -> { where(status: STATUS_OPEN) } }
end
