# frozen_string_literal: true

class Program < ApplicationRecord
  STATUS_DRAFT = "draft"
  STATUS_ACTIVE = "active"
  STATUS_ARCHIVED = "archived"
  STATUSES = [ STATUS_DRAFT, STATUS_ACTIVE, STATUS_ARCHIVED ].freeze

  belongs_to :organization
  has_many :invitations, dependent: :nullify
  has_many :projects, dependent: :restrict_with_exception
  has_many :program_enrollments, dependent: :destroy
  has_many :organization_reports, dependent: :restrict_with_exception
  has_many :self_reported_outcomes, dependent: :nullify

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :draft, -> { where(status: STATUS_DRAFT) }
  scope :active, -> { where(status: STATUS_ACTIVE) }
  scope :archived, -> { where(status: STATUS_ARCHIVED) }
  scope :filterable, -> { where(status: [ STATUS_ACTIVE, STATUS_ARCHIVED ]) }

  def draft?
    status == STATUS_DRAFT
  end

  def active?
    status == STATUS_ACTIVE
  end

  def archived?
    status == STATUS_ARCHIVED
  end

  def empty_for_delete?
    program_enrollments.none? && projects.none? && invitations.none? && organization_reports.none?
  end
end
