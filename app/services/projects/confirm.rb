# frozen_string_literal: true

module Projects
  class Confirm
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
        raise DomainError.new("Only draft projects can be confirmed", code: "validation_error") unless @project.draft?

        if ProjectMembership.active_participation?(@user)
          raise ActiveParticipationConflict
        end

        owner = @project.credit_owner
        reason = @project.workspace.organization_id.present? ? "org_project_create" : "project_create"

        Credits::Consume.call(
          owner: owner,
          amount: 1,
          reason: reason,
          idempotency_key: "project_confirm:#{@project.id}",
          actor_user: @user,
          related: @project
        )

        @project.update!(
          status: Project::STATUS_ACTIVE,
          confirmed_at: Time.current
        )

        ProjectMembership.create!(
          project: @project,
          user: @user,
          role: ProjectMembership::ROLE_CREATOR,
          status: ProjectMembership::STATUS_ACTIVE
        )
      end

      @project.reload
    end

    private

    def authorize!
      raise DomainError.new("Only the creator can confirm this project", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id
      raise DomainError.new("Not a member of this workspace", code: "forbidden", status: :forbidden) unless @user.member_of_workspace?(@project.workspace)
    end
  end
end
