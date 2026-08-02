# frozen_string_literal: true

class User < ApplicationRecord
  PENDING_ONBOARDING = "pending_onboarding"
  ACTIVE = "active"
  SUSPENDED = "suspended"

  STATUSES = [ PENDING_ONBOARDING, ACTIVE, SUSPENDED ].freeze
  AGE_STATUSES = [ AgeStatusCalculator::ADULT, AgeStatusCalculator::MINOR, AgeStatusCalculator::UNKNOWN ].freeze
  ONBOARDING_PATHS = %w[independent organization_invited].freeze

  has_one :profile, dependent: :destroy
  has_one :age_visibility_preference, dependent: :destroy
  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships
  has_many :credit_ledger_entries, as: :owner, dependent: :restrict_with_exception

  belongs_to :personal_workspace, class_name: "Workspace", optional: true
  belongs_to :active_workspace, class_name: "Workspace", optional: true

  validates :firebase_uid, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :status, inclusion: { in: STATUSES }
  validates :age_status, inclusion: { in: AGE_STATUSES }, allow_nil: true
  validates :onboarding_path, inclusion: { in: ONBOARDING_PATHS }, allow_nil: true

  def suspended?
    status == SUSPENDED
  end

  def pending_onboarding?
    status == PENDING_ONBOARDING
  end

  def adult?
    age_status == AgeStatusCalculator::ADULT
  end

  # Minors and unknown-age users get no Personal workspace, no personal trial
  # credit, and no public identity.
  def privacy_restricted?
    !adult?
  end

  def public_identity_visible?
    return false if privacy_restricted?
    return true if onboarding_path == "independent"

    # Org-derived users must clear the age-up visibility review first.
    age_visibility_preference&.public_identity_confirmed? || false
  end

  # Personal first when granted, then one workspace per organization membership.
  def usable_workspaces
    memberships = organization_memberships.includes(organization: :workspace).to_a
    organization_workspaces = memberships.filter_map { |membership| membership.organization.workspace }

    ([ personal_workspace ] + organization_workspaces).compact.uniq
  end

  def member_of_workspace?(workspace)
    return false if workspace.nil?
    return true if personal_workspace_id.present? && personal_workspace_id == workspace.id
    return false if workspace.organization_id.blank?

    organization_memberships.exists?(organization_id: workspace.organization_id)
  end

  def membership_for(organization)
    return nil if organization.nil?

    organization_memberships.find_by(organization_id: organization.id)
  end

  def can_access_org_admin_for?(workspace)
    return false if workspace&.organization_id.blank?

    organization_memberships.find_by(organization_id: workspace.organization_id)&.staff? || false
  end

  # Personal when available, otherwise the first organization workspace (A-06).
  def default_workspace
    personal_workspace || usable_workspaces.first
  end

  def resolved_active_workspace
    return active_workspace if active_workspace && member_of_workspace?(active_workspace)

    default_workspace
  end
end
