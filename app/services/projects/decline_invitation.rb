# frozen_string_literal: true

module Projects
  class DeclineInvitation
    def self.call(invitation:, user:)
      new(invitation: invitation, user: user).call
    end

    def initialize(invitation:, user:)
      @invitation = invitation
      @user = user
    end

    def call
      raise DomainError.new("Only the invitee can decline", code: "forbidden", status: :forbidden) unless @invitation.invitee_id == @user.id
      raise DomainError.new("Invitation is not pending", code: "validation_error") unless @invitation.pending?

      @invitation.update!(
        status: ProjectInvitation::STATUS_DECLINED,
        responded_at: Time.current
      )
      @invitation
    end
  end
end
