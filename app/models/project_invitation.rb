# frozen_string_literal: true

class ProjectInvitation < ApplicationRecord
  STATUS_PENDING = "pending"
  STATUS_ACCEPTED = "accepted"
  STATUS_DECLINED = "declined"
  STATUS_EXPIRED = "expired"
  STATUS_BLOCKED = "blocked"
  STATUSES = [ STATUS_PENDING, STATUS_ACCEPTED, STATUS_DECLINED, STATUS_EXPIRED, STATUS_BLOCKED ].freeze

  belongs_to :project
  belongs_to :inviter, class_name: "User"
  belongs_to :invitee, class_name: "User"

  validates :requested_role, presence: true, length: { maximum: 120 }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: STATUS_PENDING) }

  def pending?
    status == STATUS_PENDING
  end
end
