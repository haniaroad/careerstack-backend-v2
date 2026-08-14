# frozen_string_literal: true

class Organization < ApplicationRecord
  WORKSPACE_ACTIVE = "active"
  WORKSPACE_OFFBOARDING = "offboarding_readonly"
  WORKSPACE_DISABLED = "disabled"
  WORKSPACE_STATUSES = [ WORKSPACE_ACTIVE, WORKSPACE_OFFBOARDING, WORKSPACE_DISABLED ].freeze
  OFFBOARDING_DAYS = 30

  belongs_to :structure_term, class_name: "TaxonomyTerm", optional: true
  belongs_to :primary_goal_term, class_name: "TaxonomyTerm", optional: true
  has_one :workspace, dependent: :destroy
  has_many :programs, dependent: :destroy
  has_many :organization_memberships, dependent: :destroy
  has_many :users, through: :organization_memberships
  has_many :invitations, dependent: :destroy
  has_many :upgrade_requests, class_name: "OrganizationUpgradeRequest", dependent: :destroy
  has_many :credit_ledger_entries, as: :owner, dependent: :restrict_with_exception
  has_many :credit_lots, as: :owner, dependent: :restrict_with_exception

  validates :name, :country, :state_region, :timezone, presence: true
  validates :workspace_status, inclusion: { in: WORKSPACE_STATUSES }

  def workspace_active?
    workspace_status == WORKSPACE_ACTIVE
  end

  def offboarding_readonly?
    workspace_status == WORKSPACE_OFFBOARDING
  end

  def workspace_disabled?
    workspace_status == WORKSPACE_DISABLED
  end

  def writable?
    workspace_active?
  end

  def open_upgrade_request
    upgrade_requests.open_requests.order(updated_at: :desc).first
  end
end
