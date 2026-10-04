# frozen_string_literal: true

module Invitations
  # Staff resend the same pending invitation. The token rotates and the existing
  # notification is delivered again. A second invitation is not created.
  class Resend
    def self.call(actor:, organization_id:, invitation_id:)
      new(actor: actor, organization_id: organization_id, invitation_id: invitation_id).call
    end

    def initialize(actor:, organization_id:, invitation_id:)
      @actor = actor
      @organization_id = organization_id
      @invitation_id = invitation_id
    end

    def call
      access = Organizations::Access.staff!(user: @actor, organization_id: @organization_id)
      Organizations::Access.require_writable!(access.organization)
      invitation = access.organization.invitations.find(@invitation_id)
      raise Error.new("Only a pending invitation can be resent", code: "validation_error") unless invitation.usable?

      if invitation.last_sent_at.present? && invitation.last_sent_at > 15.minutes.ago
        retry_at = invitation.last_sent_at + 15.minutes
        raise Error.new(
          "You can resend this invite after #{retry_at.utc.strftime('%Y-%m-%d %H:%M UTC')}.",
          code: "resend_cooldown"
        )
      end

      unless access.membership.administrator? || invitation.role == OrganizationMembership::PARTICIPANT
        raise Error.new(
          "Only organization administrators can resend this invitation",
          code: "forbidden",
          status: :forbidden
        )
      end

      raw = invitation.rotate_token!
      invitation.update!(last_sent_at: Time.current)
      deliver!(invitation, access.organization, raw)
      invitation
    end

    private

    def deliver!(invitation, organization, raw)
      notification = Notification.find_by(
        source_type: "Invitation",
        source_id: invitation.id,
        event_key: "organization_invitation"
      )
      if notification
        notification.update!(
          email_status: "pending",
          email_skip_reason: nil,
          payload: (notification.payload || {}).merge("token" => raw)
        )
        Notifications::EnqueueDelivery.call(notification: notification)
        return
      end

      invitee = User.find_by(email: invitation.email) if invitation.email.present?
      Notifications::Hook.emit(
        event_key: "organization_invitation",
        actor: @actor,
        recipients: [ { user: invitee, email: invitation.email } ],
        source: invitation,
        organization: organization,
        payload: Notifications::Hook.org_payload(organization, "token" => raw)
      )
    end
  end
end
