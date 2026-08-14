# frozen_string_literal: true

class OrganizationMembership < ApplicationRecord
  ADMIN = "admin"
  MANAGER = "manager"
  PARTICIPANT = "participant"

  ROLES = [ ADMIN, MANAGER, PARTICIPANT ].freeze
  STAFF_ROLES = [ ADMIN, MANAGER ].freeze

  STATUS_ACTIVE = "active"
  STATUS_REMOVED = "removed"
  STATUSES = [ STATUS_ACTIVE, STATUS_REMOVED ].freeze

  belongs_to :organization
  belongs_to :user
  belongs_to :program, optional: true
  belongs_to :program_filter_program, class_name: "Program", optional: true
  belongs_to :removed_by_user, class_name: "User", optional: true
  has_many :program_enrollments, dependent: :destroy
  has_many :enrolled_programs, through: :program_enrollments, source: :program

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :organization_id }
  validate :program_belongs_to_organization

  scope :active, -> { where(status: STATUS_ACTIVE) }
  scope :removed, -> { where(status: STATUS_REMOVED) }
  scope :admins, -> { active.where(role: ADMIN) }
  scope :staff, -> { active.where(role: STAFF_ROLES) }

  def staff?
    active? && role.in?(STAFF_ROLES)
  end

  def administrator?
    active? && role == ADMIN
  end

  def manager?
    active? && role == MANAGER
  end

  def participant?
    active? && role == PARTICIPANT
  end

  def active?
    status == STATUS_ACTIVE
  end

  def removed?
    status == STATUS_REMOVED
  end

  def can_archive_programs?
    administrator?
  end

  def can_delete_empty_drafts?
    administrator?
  end

  def can_remove_members?
    administrator?
  end

  def can_view_credit_history?
    administrator?
  end

  def last_administrator?
    administrator? && organization.organization_memberships.admins.where.not(id: id).none?
  end

  def replace_enrollments!(program_ids)
    ids = Array(program_ids).compact.uniq
    programs = organization.programs.where(id: ids)
    raise DomainError.new("One or more programs were not found", code: "not_found", status: :not_found) if programs.size != ids.size

    transaction do
      program_enrollments.destroy_all
      programs.each { |program| program_enrollments.create!(program: program) }
      update!(program: programs.first)
    end
  end

  private

  def program_belongs_to_organization
    [ :program, :program_filter_program ].each do |association|
      record = public_send(association)
      next if record.nil?
      next if record.organization_id == organization_id

      errors.add(association, "must belong to the same organization")
    end
  end
end
