# frozen_string_literal: true

class Project < ApplicationRecord
  MODE_SOLO = "solo"
  MODE_TEAM = "team"
  MODES = [ MODE_SOLO, MODE_TEAM ].freeze

  JOINING_APPLICATION = "application"
  JOINING_INSTANT = "instant"
  JOINING_INVITE_ONLY = "invite_only"
  JOINING_MODES = [ JOINING_APPLICATION, JOINING_INSTANT, JOINING_INVITE_ONLY ].freeze

  RECRUITMENT_OPEN = "open"
  RECRUITMENT_FULL = "full"
  RECRUITMENT_CLOSED = "closed"

  STATUS_DRAFT = "draft"
  STATUS_ACTIVE = "active"
  STATUS_COMPLETED = "completed"
  STATUS_EXPIRED = "expired"
  STATUS_CANCELLED = "cancelled"
  STATUS_ARCHIVED = "archived"
  STATUSES = [
    STATUS_DRAFT,
    STATUS_ACTIVE,
    STATUS_COMPLETED,
    STATUS_EXPIRED,
    STATUS_CANCELLED,
    STATUS_ARCHIVED
  ].freeze

  PHASE_NORMAL = "normal"
  PHASE_ENDING_SOON = "ending_soon"
  PHASE_GRACE_PERIOD = "grace_period"
  PHASE_READ_ONLY = "read_only"
  PHASES = [ PHASE_NORMAL, PHASE_ENDING_SOON, PHASE_GRACE_PERIOD, PHASE_READ_ONLY ].freeze

  SOURCE_MANUAL = "manual"
  SOURCE_AI = "ai"
  SOURCES = [ SOURCE_MANUAL, SOURCE_AI ].freeze

  GRACE_DAYS = 7
  ENDING_SOON_DAYS = 7

  belongs_to :workspace
  belongs_to :creator, class_name: "User"
  has_many :memberships, class_name: "ProjectMembership", dependent: :destroy
  has_many :members, through: :memberships, source: :user
  has_many :ai_generations, dependent: :nullify
  has_many :tasks, dependent: :destroy
  has_many :applications, class_name: "ProjectApplication", dependent: :destroy
  has_many :invitations, class_name: "ProjectInvitation", dependent: :destroy

  validates :title, presence: true, length: { maximum: 120 }
  validates :summary, length: { maximum: 2000 }, allow_nil: true
  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :joining_mode, inclusion: { in: JOINING_MODES }, allow_nil: true
  validates :capacity, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }, allow_nil: true
  validate :skills_are_strings
  validate :roles_needed_are_strings
  validate :proposed_tasks_are_array
  validate :team_fields_consistency

  scope :in_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :drafts, -> { where(status: STATUS_DRAFT) }
  scope :active, -> { where(status: STATUS_ACTIVE) }

  def draft?
    status == STATUS_DRAFT
  end

  def active?
    status == STATUS_ACTIVE
  end

  def completed?
    status == STATUS_COMPLETED
  end

  def expired?
    status == STATUS_EXPIRED
  end

  def cancelled?
    status == STATUS_CANCELLED
  end

  def archived?
    status == STATUS_ARCHIVED
  end

  def solo?
    mode == MODE_SOLO
  end

  def team?
    mode == MODE_TEAM
  end

  def ai_sourced?
    source == SOURCE_AI
  end

  def ai_generation_succeeded?
    ai_generation_succeeded_at.present?
  end

  def credit_owner
    if workspace.organization_id.present?
      workspace.organization
    else
      workspace.owner_user
    end
  end

  def active_participant_count
    memberships.active.participants.count
  end

  def seats_remaining
    return 0 unless team? && capacity.present?

    [ capacity - active_participant_count, 0 ].max
  end

  # Derived lifecycle phase (UTC calendar dates). Not persisted.
  def phase
    return PHASE_READ_ONLY if completed? || expired? || cancelled? || archived?
    return PHASE_NORMAL unless active?
    return PHASE_NORMAL if ends_on.blank?

    today = utc_today
    if today <= ends_on - (ENDING_SOON_DAYS + 1).days
      PHASE_NORMAL
    elsif today <= ends_on
      PHASE_ENDING_SOON
    else
      # Includes days past final expiration while status is still active (until Evaluate runs).
      PHASE_GRACE_PERIOD
    end
  end

  def final_expires_at
    return nil if ends_on.blank?

    (ends_on + GRACE_DAYS.days).in_time_zone("UTC").end_of_day
  end

  def past_final_expiration?
    return false if ends_on.blank?

    utc_today > ends_on + GRACE_DAYS.days
  end

  def grace_period?
    phase == PHASE_GRACE_PERIOD
  end

  def ending_soon?
    phase == PHASE_ENDING_SOON
  end

  def read_only_phase?
    phase == PHASE_READ_ONLY
  end

  def recruitment_state
    return nil unless team?
    return RECRUITMENT_CLOSED unless active?
    return RECRUITMENT_CLOSED if grace_period? || past_final_expiration? || completed? || expired?
    return RECRUITMENT_FULL if seats_remaining <= 0

    RECRUITMENT_OPEN
  end

  def joinable?
    team? && active? && recruitment_state == RECRUITMENT_OPEN
  end

  def ensure_lifecycle_current!
    return self unless active? && past_final_expiration?

    Projects::Lifecycle::Evaluate.call(project: self)
    reload
  end

  def non_creator_memberships_exist?
    memberships.where.not(role: ProjectMembership::ROLE_CREATOR).exists?
  end

  private

  def utc_today
    Time.find_zone!("UTC").today
  end

  def skills_are_strings
    return if skills.blank?
    return if skills.is_a?(Array) && skills.all? { |s| s.is_a?(String) }

    errors.add(:skills, "must be an array of strings")
  end

  def roles_needed_are_strings
    return if roles_needed.blank?
    return if roles_needed.is_a?(Array) && roles_needed.all? { |s| s.is_a?(String) }

    errors.add(:roles_needed, "must be an array of strings")
  end

  def proposed_tasks_are_array
    return if proposed_tasks.is_a?(Array)

    errors.add(:proposed_tasks, "must be an array")
  end

  def team_fields_consistency
    if team?
      errors.add(:joining_mode, "is required for team projects") if joining_mode.blank?
      errors.add(:capacity, "is required for team projects") if capacity.blank?
      if roles_needed.blank?
        errors.add(:roles_needed, "must include at least one role for team projects")
      end
    elsif solo?
      errors.add(:joining_mode, "must be blank for solo projects") if joining_mode.present?
      errors.add(:capacity, "must be blank for solo projects") if capacity.present?
    end
  end
end
