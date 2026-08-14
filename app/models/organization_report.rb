# frozen_string_literal: true

class OrganizationReport < ApplicationRecord
  FORMAT_PDF = "pdf"
  FORMAT_CSV = "csv"
  FORMATS = [ FORMAT_PDF, FORMAT_CSV ].freeze

  STATUS_DRAFT = "draft"
  STATUS_GENERATING = "generating"
  STATUS_READY = "ready"
  STATUS_FAILED = "failed"
  STATUSES = [ STATUS_DRAFT, STATUS_GENERATING, STATUS_READY, STATUS_FAILED ].freeze

  METHODOLOGY_NOTE = "Figures are a snapshot at generation time. Opportunity rates are self-reported and unverified. Rates with a zero denominator are omitted."

  belongs_to :organization
  belongs_to :program, optional: true
  belongs_to :requested_by, class_name: "User"
  has_many :audits, class_name: "OrganizationReportAudit", dependent: :destroy
  has_one_attached :file

  validates :format, inclusion: { in: FORMATS }
  validates :status, inclusion: { in: STATUSES }
  validates :period_starts_on, :period_ends_on, presence: true
  validate :period_order
  validate :program_belongs_to_organization

  scope :generating, -> { where(status: STATUS_GENERATING) }
  scope :for_program, ->(program_id) { where(program_id: program_id) }

  def draft?
    status == STATUS_DRAFT
  end

  def generating?
    status == STATUS_GENERATING
  end

  def ready?
    status == STATUS_READY
  end

  def failed?
    status == STATUS_FAILED
  end

  def title
    "#{program&.name.presence || "All programs"} · #{period_label}"
  end

  def period_label
    "#{period_starts_on.strftime("%b %-d, %Y")} – #{period_ends_on.strftime("%b %-d, %Y")}"
  end

  private

  def period_order
    return if period_starts_on.blank? || period_ends_on.blank?
    return if period_starts_on <= period_ends_on

    errors.add(:period_ends_on, "must be on or after the start date")
  end

  def program_belongs_to_organization
    return if program_id.blank? || program.nil?
    return if program.organization_id == organization_id

    errors.add(:program, "must belong to the organization")
  end
end
