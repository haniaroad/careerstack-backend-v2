# frozen_string_literal: true

class ProjectMembership < ApplicationRecord
  ROLE_CREATOR = "creator"
  ROLE_PARTICIPANT = "participant"
  ROLES = [ ROLE_CREATOR, ROLE_PARTICIPANT ].freeze

  STATUS_ACTIVE = "active"
  STATUS_DEPARTED = "departed"
  STATUS_REMOVED = "removed"
  STATUS_ENDED = "ended"
  STATUSES = [ STATUS_ACTIVE, STATUS_DEPARTED, STATUS_REMOVED, STATUS_ENDED ].freeze

  JOIN_SOURCE_INSTANT = "instant"
  JOIN_SOURCE_APPLICATION = "application"
  JOIN_SOURCE_INVITE = "invite"
  JOIN_SOURCE_ASSIGN = "assign"
  JOIN_SOURCES = [
    JOIN_SOURCE_INSTANT,
    JOIN_SOURCE_APPLICATION,
    JOIN_SOURCE_INVITE,
    JOIN_SOURCE_ASSIGN
  ].freeze

  belongs_to :project
  belongs_to :user
  has_many :events, class_name: "ProjectMembershipEvent", dependent: :destroy

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :project_id }
  validates :join_source, inclusion: { in: JOIN_SOURCES }, allow_nil: true
  validates :participant_role, presence: true, if: -> { role == ROLE_PARTICIPANT && status == STATUS_ACTIVE }

  scope :active, -> { where(status: STATUS_ACTIVE) }
  scope :participants, -> { where(role: ROLE_PARTICIPANT) }
  scope :creators, -> { where(role: ROLE_CREATOR) }

  # A person may create many team projects. They may be the worker on only one
  # active project: a participant membership, or a solo project they created.
  def self.active_participation?(user)
    active.joins(:project).where(projects: { status: Project::STATUS_ACTIVE }, user_id: user.id).where(
      "project_memberships.role = :participant OR (project_memberships.role = :creator AND projects.mode = :solo)",
      participant: ROLE_PARTICIPANT,
      creator: ROLE_CREATOR,
      solo: Project::MODE_SOLO
    ).exists?
  end

  def creator?
    role == ROLE_CREATOR
  end

  def participant?
    role == ROLE_PARTICIPANT
  end

  def active?
    status == STATUS_ACTIVE
  end
end
