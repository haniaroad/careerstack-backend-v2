# frozen_string_literal: true

module Projects
  class InstantJoin
    def self.call(project:, user:, participant_role:)
      new(project: project, user: user, participant_role: participant_role).call
    end

    def initialize(project:, user:, participant_role:)
      @project = project
      @user = user
      @participant_role = participant_role
    end

    def call
      Projects::JoinEligibility.assert_can_join!(project: @project, user: @user)
      Projects::Lifecycle::ActionGate.assert!(project: @project, action: :join)
      unless @project.joining_mode == Project::JOINING_INSTANT
        raise DomainError.new("This project does not allow instant join", code: "validation_error")
      end

      Projects::CreateMembership.call(
        project: @project,
        user: @user,
        participant_role: @participant_role,
        source: ProjectMembership::JOIN_SOURCE_INSTANT,
        actor_user: @user,
        idempotency_key: "membership_join:#{@project.id}:#{@user.id}:instant"
      )
    end
  end
end
