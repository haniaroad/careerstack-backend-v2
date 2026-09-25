# frozen_string_literal: true

module ProjectMessages
  class Create
    def self.call(project:, actor:, body:)
      new(project: project, actor: actor, body: body).call
    end

    def initialize(project:, actor:, body:)
      @project = project
      @actor = actor
      @body = body.to_s.strip
    end

    def call
      Access.membership!(project: @project, user: @actor)
      raise DomainError.new("Message cannot be empty", code: "validation_error") if @body.blank?
      raise DomainError.new("Message is too long", code: "validation_error") if @body.length > ProjectMessage::MAX_BODY_LENGTH

      message = @project.messages.create!(author: @actor, body: @body)
      NotifyUnread.call(message: message)
      message
    end
  end
end
