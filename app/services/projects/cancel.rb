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

        Credits::Restore.call(
          owner: @project.credit_owner,
          amount: 1,
          reason: "cancellation_restore",
          idempotency_key: "project_cancel_restore:#{@project.id}:#{@user.id}",
          actor_user: @user,
          related: @project
        )

        @project.memberships.active.find_each do |membership|
          membership.update!(status: ProjectMembership::STATUS_ENDED)
        end

        @project.update!(
          status: Project::STATUS_CANCELLED,
          cancelled_at: Time.current
        )
      end

      @project.reload
    end

    private

    def authorize!
      raise DomainError.new("Only the creator can cancel this project", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id
      raise DomainError.new("Not a member of this workspace", code: "forbidden", status: :forbidden) unless @user.member_of_workspace?(@project.workspace)
    end
  end
end
