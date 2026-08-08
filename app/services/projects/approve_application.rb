# frozen_string_literal: true

module Projects
  class ApproveApplication
    def self.call(application:, user:)
      new(application: application, user: user).call
    end

    def initialize(application:, user:)
      @application = application
      @user = user
    end

    def call
      project = @application.project
      authorize!(project)
      raise DomainError.new("Application is not pending", code: "validation_error") unless @application.pending?

      membership = nil
      ActiveRecord::Base.transaction do
        @application.lock!
        raise DomainError.new("Application is not pending", code: "validation_error") unless @application.pending?

        membership = Projects::CreateMembership.call(
          project: project,
          user: @application.applicant,
          participant_role: @application.requested_role,
          source: ProjectMembership::JOIN_SOURCE_APPLICATION,
          actor_user: @user,
          idempotency_key: "membership_join:#{project.id}:#{@application.applicant_id}:application:#{@application.id}"
        )

        @application.update!(
          status: ProjectApplication::STATUS_APPROVED,
          reviewed_by: @user,
          reviewed_at: Time.current
        )
      end

      { application: @application.reload, membership: membership }
    end

    private

    def authorize!(project)
      raise DomainError.new("Only the creator can approve applications", code: "forbidden", status: :forbidden) unless project.creator_id == @user.id
    end
  end
end
