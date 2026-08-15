# frozen_string_literal: true

module Projects
  class RejectApplication
    def self.call(application:, user:, reason:)
      new(application: application, user: user, reason: reason).call
    end

    def initialize(application:, user:, reason:)
      @application = application
      @user = user
      @reason = reason.to_s.strip
    end

    def call
      project = @application.project
      raise DomainError.new("Only the creator can reject applications", code: "forbidden", status: :forbidden) unless project.creator_id == @user.id
      raise DomainError.new("Application is not pending", code: "validation_error") unless @application.pending?
      raise DomainError.new("Rejection reason is required", code: "validation_error") if @reason.blank?

      @application.update!(
        status: ProjectApplication::STATUS_REJECTED,
        rejection_reason: @reason,
        reviewed_by: @user,
        reviewed_at: Time.current
      )
      Notifications::Hook.emit(
        event_key: "application_decision",
        actor: @user,
        recipients: [ @application.applicant ],
        source: @application,
        project: project,
        payload: Notifications::Hook.project_payload(project, "decision_label" => "not selected")
      )
      @application
    end
  end
end
