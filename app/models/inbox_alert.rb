# frozen_string_literal: true

class InboxAlert < ApplicationRecord
  AUDIENCE_USER = "user"
  AUDIENCE_ORG_STAFF = "org_staff"
  AUDIENCES = [ AUDIENCE_USER, AUDIENCE_ORG_STAFF ].freeze

  KIND_CREATOR_REMINDER = "creator_reminder"
  KIND_ESCALATION = "escalation"
  KIND_DECISION = "decision"
  KIND_LIFECYCLE = "lifecycle"
  KINDS = [ KIND_CREATOR_REMINDER, KIND_ESCALATION, KIND_DECISION, KIND_LIFECYCLE ].freeze

  URGENCY_CRITICAL = "critical"
  URGENCY_HIGH = "high"
  URGENCY_MEDIUM = "medium"
  URGENCY_LOW = "low"
  URGENCIES = [ URGENCY_CRITICAL, URGENCY_HIGH, URGENCY_MEDIUM, URGENCY_LOW ].freeze

  belongs_to :workspace
  belongs_to :recipient_user, class_name: "User", optional: true
  belongs_to :organization, optional: true
  belongs_to :project, optional: true

  validates :audience, inclusion: { in: AUDIENCES }
  validates :kind, inclusion: { in: KINDS }
  validates :urgency, inclusion: { in: URGENCIES }
  validates :subject_type, :subject_id, :title, :body, :idempotency_key, presence: true
end
