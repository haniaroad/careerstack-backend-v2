# frozen_string_literal: true

module Projects
  class Leave
    def self.call(project:, user:, reason_category:, reason_detail: nil)
      new(project: project, user: user, reason_category: reason_category, reason_detail: reason_detail).call
    end

    def initialize(project:, user:, reason_category:, reason_detail:)
      @project = project
      @user = user
      @reason_category = reason_category.to_s
      @reason_detail = reason_detail.to_s.strip.presence
    end

    def call
      unless ProjectMembershipEvent::REASON_CATEGORIES.include?(@reason_category)
        raise DomainError.new("Invalid reason category", code: "validation_error")
      end

      Projects::Lifecycle::ActionGate.assert!(project: @project, action: :leave)

      ActiveRecord::Base.transaction do
        @project.lock!
        Projects::Lifecycle::ActionGate.assert!(project: @project.reload, action: :leave)
        membership = @project.memberships.active.find_by(user_id: @user.id)
        raise DomainError.new("Not an active participant", code: "validation_error") if membership.nil?
        raise DomainError.new("Creator cannot leave; cancel the project instead", code: "validation_error") if membership.creator?

        membership.update!(status: ProjectMembership::STATUS_DEPARTED)
        ProjectMembershipEvent.create!(
          project_membership: membership,
          project: @project,
          user: @user,
          actor_user: @user,
          event_type: ProjectMembershipEvent::EVENT_DEPARTED,
          reason_category: @reason_category,
          reason_detail: @reason_detail
        )

        Tasks::UnassignMember.call(project: @project, user: @user)
        membership
      end.tap do
        Notifications::Hook.emit(
          event_key: "participant_left",
          actor: @user,
          recipients: [ @project.creator ],
          source: @project,
          project: @project,
          payload: Notifications::Hook.project_payload(@project)
        )
      end
    end
  end
end
