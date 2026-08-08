# frozen_string_literal: true

module Projects
  class CreateMembership
    def self.call(project:, user:, participant_role:, source:, actor_user:, idempotency_key: nil)
      new(
        project: project,
        user: user,
        participant_role: participant_role,
        source: source,
        actor_user: actor_user,
        idempotency_key: idempotency_key
      ).call
    end

    def initialize(project:, user:, participant_role:, source:, actor_user:, idempotency_key:)
      @project = project
      @user = user
      @participant_role = participant_role.to_s.strip
      @source = source.to_s
      @actor_user = actor_user
      @idempotency_key = idempotency_key.presence || "membership_join:#{project.id}:#{user.id}"
    end

    def call
      validate_inputs!

      ActiveRecord::Base.transaction do
        @project.lock!

        existing = @project.memberships.find_by(user_id: @user.id)
        if existing&.active?
          return existing
        end

        unless @project.team? && @project.active?
          raise DomainError.new("Project is not joinable", code: "validation_error")
        end
        if @project.seats_remaining <= 0
          raise DomainError.new("Project is at capacity", code: "capacity_full", status: :conflict)
        end

        if ProjectMembership.active_participation?(@user)
          raise ActiveParticipationConflict
        end

        if @user.id == @project.creator_id
          raise DomainError.new("Creator cannot join as a participant", code: "validation_error")
        end

        reason = @project.workspace.organization_id.present? ? "org_membership_join" : "membership_join"
        Credits::Consume.call(
          owner: Projects::JoinEligibility.credit_owner_for_join(project: @project, user: @user),
          amount: 1,
          reason: reason,
          idempotency_key: @idempotency_key,
          actor_user: @actor_user,
          related: @project
        )

        membership = if existing
          existing.update!(
            role: ProjectMembership::ROLE_PARTICIPANT,
            status: ProjectMembership::STATUS_ACTIVE,
            participant_role: @participant_role,
            join_source: @source
          )
          existing
        else
          ProjectMembership.create!(
            project: @project,
            user: @user,
            role: ProjectMembership::ROLE_PARTICIPANT,
            status: ProjectMembership::STATUS_ACTIVE,
            participant_role: @participant_role,
            join_source: @source
          )
        end

        ProjectMembershipEvent.create!(
          project_membership: membership,
          project: @project,
          user: @user,
          actor_user: @actor_user,
          event_type: ProjectMembershipEvent::EVENT_JOINED,
          join_source: @source,
          participant_role: @participant_role
        )

        expire_pending_for_user!

        if @project.seats_remaining <= 0
          expire_open_recruitment!
        end

        membership
      end
    end

    private

    def validate_inputs!
      raise DomainError.new("Participant role is required", code: "validation_error") if @participant_role.blank?
      unless ProjectMembership::JOIN_SOURCES.include?(@source)
        raise DomainError.new("Invalid join source", code: "validation_error")
      end
      raise DomainError.new("Only team projects accept memberships", code: "validation_error") unless @project.team?
    end

    def expire_pending_for_user!
      @project.applications.pending.where(applicant_id: @user.id).find_each do |app|
        app.update!(status: ProjectApplication::STATUS_EXPIRED)
      end
      @project.invitations.pending.where(invitee_id: @user.id).find_each do |invite|
        invite.update!(status: ProjectInvitation::STATUS_EXPIRED, responded_at: Time.current)
      end
    end

    def expire_open_recruitment!
      @project.applications.pending.find_each do |app|
        app.update!(status: ProjectApplication::STATUS_EXPIRED)
      end
      @project.invitations.pending.find_each do |invite|
        invite.update!(status: ProjectInvitation::STATUS_EXPIRED, responded_at: Time.current)
      end
    end
  end
end
