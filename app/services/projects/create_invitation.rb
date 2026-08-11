# frozen_string_literal: true

module Projects
  class CreateInvitation
    def self.call(project:, inviter:, invitee:, requested_role:)
      new(project: project, inviter: inviter, invitee: invitee, requested_role: requested_role).call
    end

    def initialize(project:, inviter:, invitee:, requested_role:)
      @project = project
      @inviter = inviter
      @invitee = invitee
      @requested_role = requested_role
    end

    def call
      raise DomainError.new("Only the creator can invite", code: "forbidden", status: :forbidden) unless @project.creator_id == @inviter.id
      raise DomainError.new("Only team projects accept invitations", code: "validation_error") unless @project.team?
      Projects::Lifecycle::ActionGate.assert!(project: @project, action: :join)
      raise DomainError.new("Project is not accepting invites", code: "validation_error") unless @project.joinable?
      raise DomainError.new("Cannot invite the creator", code: "validation_error") if @invitee.id == @project.creator_id
      Projects::JoinEligibility.assert_can_join!(project: @project, user: @invitee)

      if ProjectMembership.active_participation?(@invitee)
        raise DomainError.new("Invitee is unavailable due to another active participation", code: "invitee_unavailable", status: :conflict)
      end

      if @project.invitations.pending.exists?(invitee_id: @invitee.id)
        raise DomainError.new("Invitee already has a pending invitation", code: "validation_error")
      end

      ProjectInvitation.create!(
        project: @project,
        inviter: @inviter,
        invitee: @invitee,
        requested_role: @requested_role.to_s.strip,
        status: ProjectInvitation::STATUS_PENDING
      )
    end
  end
end
