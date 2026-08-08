# frozen_string_literal: true

module Projects
  class AcceptInvitation
    def self.call(invitation:, user:)
      new(invitation: invitation, user: user).call
    end

    def initialize(invitation:, user:)
      @invitation = invitation
      @user = user
    end

    def call
      raise DomainError.new("Only the invitee can accept", code: "forbidden", status: :forbidden) unless @invitation.invitee_id == @user.id
      raise DomainError.new("Invitation is not pending", code: "validation_error") unless @invitation.pending?

      membership = nil
      ActiveRecord::Base.transaction do
        @invitation.lock!
        raise DomainError.new("Invitation is not pending", code: "validation_error") unless @invitation.pending?

        membership = Projects::CreateMembership.call(
          project: @invitation.project,
          user: @user,
          participant_role: @invitation.requested_role,
          source: ProjectMembership::JOIN_SOURCE_INVITE,
          actor_user: @user,
          idempotency_key: "membership_join:#{@invitation.project_id}:#{@user.id}:invite:#{@invitation.id}"
        )

        @invitation.update!(
          status: ProjectInvitation::STATUS_ACCEPTED,
          responded_at: Time.current
        )
      end

      { invitation: @invitation.reload, membership: membership }
    end
  end
end
