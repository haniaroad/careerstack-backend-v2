# frozen_string_literal: true

class OrganizationUpgradeRequest < ApplicationRecord
  STATUS_OPEN = "open"
  STATUS_CONTACTED = "contacted"
  STATUS_CLOSED = "closed"
  STATUSES = [ STATUS_OPEN, STATUS_CONTACTED, STATUS_CLOSED ].freeze

  belongs_to :organization
  belongs_to :requesting_user, class_name: "User"

  validates :expected_participants, :expected_projects_or_cohorts, :timeline, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :open_requests, -> { where(status: STATUS_OPEN) }

  def open?
    status == STATUS_OPEN
  end
end
