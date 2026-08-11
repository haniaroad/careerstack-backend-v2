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
        validate_ends_on!
        validate_team_ready! if @project.team?

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

        assignee = @project.solo? ? @user : nil
        Tasks::MaterializeFromProposed.call(project: @project, assignee: assignee)
      end

      @project.reload
    end

    private

    def authorize!
      raise DomainError.new("Only the creator can confirm this project", code: "forbidden", status: :forbidden) unless @project.creator_id == @user.id
      raise DomainError.new("Not a member of this workspace", code: "forbidden", status: :forbidden) unless @user.member_of_workspace?(@project.workspace)
    end

    def validate_ends_on!
      if @project.ends_on.blank?
        raise DomainError.new("ends_on is required to confirm a project", code: "validation_error")
      end
      if @project.ends_on < Time.find_zone!("UTC").today
        raise DomainError.new("ends_on must be today or in the future", code: "validation_error")
      end
    end

    def validate_team_ready!
      unless Project::JOINING_MODES.include?(@project.joining_mode.to_s)
        raise DomainError.new("Joining mode is required for team projects", code: "validation_error")
      end
      unless @project.capacity.to_i.between?(1, 5)
        raise DomainError.new("Capacity must be between 1 and 5", code: "validation_error")
      end
      if Array(@project.roles_needed).blank?
        raise DomainError.new("At least one role is required for team projects", code: "validation_error")
      end
    end
  end
end
