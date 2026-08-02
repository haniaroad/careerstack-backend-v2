# frozen_string_literal: true

class OrganizationMembership < ApplicationRecord
  ADMIN = "admin"
  MANAGER = "manager"
  PARTICIPANT = "participant"

  ROLES = [ ADMIN, MANAGER, PARTICIPANT ].freeze
  STAFF_ROLES = [ ADMIN, MANAGER ].freeze

  belongs_to :organization
  belongs_to :user
  belongs_to :program, optional: true
  belongs_to :program_filter_program, class_name: "Program", optional: true

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :organization_id }
  validate :program_belongs_to_organization

  # Roles allowed to reach organization administration surfaces.
  def staff?
    role.in?(STAFF_ROLES)
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
