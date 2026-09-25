# frozen_string_literal: true

module ProjectMessages
  class CreateReport
    def self.call(message:, actor:, report_type:, reason_category:, details: nil)
      new(
        message: message,
        actor: actor,
        report_type: report_type,
        reason_category: reason_category,
        details: details
      ).call
    end

    def initialize(message:, actor:, report_type:, reason_category:, details:)
      @message = message
      @actor = actor
      @report_type = report_type.to_s
      @reason_category = reason_category.to_s
      @details = details.to_s.presence
    end

    def call
      Access.membership!(project: @message.project, user: @actor)
      raise DomainError.new("You cannot report your own message", code: "forbidden", status: :forbidden) if @message.author_id == @actor.id
      raise DomainError.new("Invalid report type", code: "validation_error") unless ProjectMessageReport::REPORT_TYPES.include?(@report_type)
      raise DomainError.new("Invalid reason category", code: "validation_error") unless ProjectMessageReport::REASON_CATEGORIES.include?(@reason_category)

      ProjectMessageReport.create!(
        project_message: @message,
        reporter: @actor,
        report_type: @report_type,
        reason_category: @reason_category,
        details: @details,
        status: ProjectMessageReport::STATUS_OPEN
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      raise DomainError.new("You already reported this message", code: "validation_error")
    end
  end
end
