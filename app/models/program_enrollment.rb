# frozen_string_literal: true

class ProgramEnrollment < ApplicationRecord
  belongs_to :organization_membership
  belongs_to :program

  validates :program_id, uniqueness: { scope: :organization_membership_id }
  validate :program_belongs_to_membership_organization

  private

  def program_belongs_to_membership_organization
    return if program.nil? || organization_membership.nil?
    return if program.organization_id == organization_membership.organization_id

    errors.add(:program, "must belong to the same organization")
  end
end
