# frozen_string_literal: true

class OrganizationMembershipSerializer
  def self.call(membership)
    programs = membership.enrolled_programs.order(:name)
    {
      id: membership.id,
      organization_id: membership.organization_id,
      user_id: membership.user_id,
      display_name: membership.user.profile&.display_name,
      email: membership.user.email,
      role: membership.role,
      status: membership.status,
      age_status: membership.user.age_status,
      program_ids: programs.map(&:id),
      program_names: programs.map(&:name),
      is_last_administrator: membership.last_administrator?,
      can_remove: membership.active? && !membership.last_administrator?,
      joined_at: membership.created_at,
      removed_at: membership.removed_at,
      removed_reason: membership.removed_reason
    }
  end
end
