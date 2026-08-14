# frozen_string_literal: true

class OrganizationReportAudit < ApplicationRecord
  ACTION_GENERATE = "generate"
  ACTION_DOWNLOAD = "download"
  ACTIONS = [ ACTION_GENERATE, ACTION_DOWNLOAD ].freeze

  belongs_to :organization
  belongs_to :organization_report
  belongs_to :actor, class_name: "User"

  validates :action, inclusion: { in: ACTIONS }
  validates :format, inclusion: { in: OrganizationReport::FORMATS }
  validates :occurred_at, presence: true
end
