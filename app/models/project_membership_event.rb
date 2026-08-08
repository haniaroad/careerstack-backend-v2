# frozen_string_literal: true

class ProjectMembershipEvent < ApplicationRecord
  EVENT_JOINED = "joined"
  EVENT_DEPARTED = "departed"
  EVENT_REMOVED = "removed"
  EVENT_ENDED = "ended"
  EVENT_TYPES = [ EVENT_JOINED, EVENT_DEPARTED, EVENT_REMOVED, EVENT_ENDED ].freeze

  REASON_CATEGORIES = %w[
    schedule_conflict
    project_mismatch
    creator_unresponsive
    participant_unresponsive
    conduct_issue
    removed_by_creator
    removed_by_organization
    personal_reason
    other
  ].freeze

  belongs_to :project_membership
  belongs_to :project
  belongs_to :user
  belongs_to :actor_user, class_name: "User", optional: true

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :reason_category, inclusion: { in: REASON_CATEGORIES }, allow_nil: true

  before_validation :set_created_at, on: :create

  private

  def set_created_at
    self.created_at ||= Time.current
  end
end
