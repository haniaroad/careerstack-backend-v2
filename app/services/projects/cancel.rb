# frozen_string_literal: true

module Projects
  class Cancel
    def self.call(project:, user:)
      new(project: project, user: user).call
    end

    def initialize(project:, user:)
      @project = project
      @user = user
    end

    def call
      authorize!

      ActiveRecord::Base.transaction do
        @project.lock!
        return @project if @project.cancelled?
        raise DomainError.new("Only active projects can be cancelled", code: "validation_error") unless @project.active?

        if @project.solo?
          restore_solo_create_credit!
        else
          restore_team_join_credits!
        end

        @project.memberships.active.find_each do |membership|
          membership.update!(status: ProjectMembership::STATUS_ENDED)
          ProjectMembershipEvent.create!(
            project_membership: membership,
            project: @project,
            user: membership.user,
            actor_user: @user,
            event_type: ProjectMembershipEvent::EVENT_ENDED
          )
        end

        @project.update!(
          status: Project::STATUS_CANCELLED,
          cancelled_at: Time.current
        )
      end

      recipients = @project.memberships.flat_map { |membership| membership.user }.uniq
      Notifications::Hook.emit(
        event_key: "project_cancelled",
        actor: @user,
        recipients: recipients,
        source: @project,
        project: @project,
        payload: Notifications::Hook.project_payload(@project)
      )

      @project.reload
    end

    private

    def authorize!
      raise DomainError.new("Only the creator can cancel this project", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id
      raise DomainError.new("Not a member of this workspace", code: "forbidden", status: :forbidden) unless @user.member_of_workspace?(@project.workspace)
    end

    def restore_solo_create_credit!
      Credits::Restore.call(
        owner: @project.credit_owner,
        amount: 1,
        reason: "cancellation_restore",
        idempotency_key: "project_cancel_restore:#{@project.id}:#{@user.id}",
        actor_user: @user,
        related: @project
      )
    end

    def restore_team_join_credits!
      @project.memberships.active.participants.find_each do |membership|
        Credits::Restore.call(
          owner: Projects::JoinEligibility.credit_owner_for_membership_restore(project: @project, membership: membership),
          amount: 1,
          reason: "membership_cancel_restore",
          idempotency_key: "membership_cancel_restore:#{membership.id}",
          actor_user: @user,
          related: membership
        )
      end
    end
  end
end
