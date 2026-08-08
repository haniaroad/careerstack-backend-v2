# frozen_string_literal: true

class Project < ApplicationRecord
  MODE_SOLO = "solo"
  MODES = [ MODE_SOLO ].freeze

  STATUS_DRAFT = "draft"
  STATUS_ACTIVE = "active"
  STATUS_CANCELLED = "cancelled"
  STATUSES = [ STATUS_DRAFT, STATUS_ACTIVE, STATUS_CANCELLED ].freeze

  SOURCE_MANUAL = "manual"
  SOURCE_AI = "ai"
  SOURCES = [ SOURCE_MANUAL, SOURCE_AI ].freeze

  belongs_to :workspace
  belongs_to :creator, class_name: "User"
  has_many :memberships, class_name: "ProjectMembership", dependent: :destroy
  has_many :members, through: :memberships, source: :user
  has_many :ai_generations, dependent: :nullify
  has_many :tasks, dependent: :destroy

  validates :title, presence: true, length: { maximum: 120 }
  validates :summary, length: { maximum: 2000 }, allow_nil: true
  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validate :skills_are_strings
  validate :roles_needed_are_strings
  validate :proposed_tasks_are_array

  scope :in_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :drafts, -> { where(status: STATUS_DRAFT) }
  scope :active, -> { where(status: STATUS_ACTIVE) }

  def draft?
    status == STATUS_DRAFT
  end

  def active?
    status == STATUS_ACTIVE
  end

  def cancelled?
    status == STATUS_CANCELLED
  end

  def solo?
    mode == MODE_SOLO
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

  private

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
end
