# frozen_string_literal: true

module Projects
  class RemoveMember
    def self.call(project:, actor:, member_user:, reason_category:, reason_detail: nil)
      new(
        project: project,
        actor: actor,
        member_user: member_user,
        reason_category: reason_category,
        reason_detail: reason_detail
      ).call
    end

    def initialize(project:, actor:, member_user:, reason_category:, reason_detail:)
      @project = project
      @actor = actor
      @member_user = member_user
      @reason_category = reason_category.to_s
      @reason_detail = reason_detail.to_s.strip.presence
    end

    def call
      unless ProjectMembershipEvent::REASON_CATEGORIES.include?(@reason_category)
        raise DomainError.new("Invalid reason category", code: "validation_error")
      end
      authorize!

      ActiveRecord::Base.transaction do
        @project.lock!
        membership = @project.memberships.active.find_by(user_id: @member_user.id)
        raise DomainError.new("Not an active participant", code: "validation_error") if membership.nil?
        raise DomainError.new("Cannot remove the creator", code: "validation_error") if membership.creator?

        membership.update!(status: ProjectMembership::STATUS_REMOVED)
        ProjectMembershipEvent.create!(
          project_membership: membership,
          project: @project,
          user: @member_user,
          actor_user: @actor,
          event_type: ProjectMembershipEvent::EVENT_REMOVED,
          reason_category: @reason_category,
          reason_detail: @reason_detail
        )

        Tasks::UnassignMember.call(project: @project, user: @member_user)
        membership
      end
    end

    private

    def authorize!
      return if @project.creator_id == @actor.id

      workspace = @project.workspace
      if workspace.organization_id.present?
        org_membership = workspace.organization.memberships.find_by(user_id: @actor.id)
        return if org_membership&.staff?
      end

      raise DomainError.new("Not authorized to remove members", code: "forbidden", status: :forbidden)
    end
  end
end
