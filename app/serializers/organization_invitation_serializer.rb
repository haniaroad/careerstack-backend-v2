# frozen_string_literal: true

class OrganizationInvitationSerializer
  def self.call(invitation)
    {
      id: invitation.id,
      organization_id: invitation.organization_id,
      email: invitation.email,
      role: invitation.role,
      program_id: invitation.program_id,
      program_name: invitation.program&.name,
      status: invitation_status(invitation),
      invited_by_name: invitation.created_by_user&.profile&.display_name,
      expires_at: invitation.expires_at,
      accepted_at: invitation.accepted_at,
      created_at: invitation.created_at
    }
  end

  def self.invitation_status(invitation)
    return "accepted" if invitation.accepted?
    return "expired" if invitation.expired?

    "pending"
  end
end
