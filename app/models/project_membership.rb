# frozen_string_literal: true

class ProjectMembership < ApplicationRecord
  ROLE_CREATOR = "creator"
  ROLES = [ ROLE_CREATOR ].freeze

  STATUS_ACTIVE = "active"
  STATUS_ENDED = "ended"
  STATUSES = [ STATUS_ACTIVE, STATUS_ENDED ].freeze

  belongs_to :project
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :project_id }

  scope :active, -> { where(status: STATUS_ACTIVE) }

  def self.active_participation?(user)
    active.exists?(user_id: user.id)
  end
end
