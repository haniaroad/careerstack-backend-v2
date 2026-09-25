# frozen_string_literal: true

module ProjectMessages
  class List
    def self.call(project:, actor:)
      new(project: project, actor: actor).call
    end

    def initialize(project:, actor:)
      @project = project
      @actor = actor
    end

    def call
      membership = Access.membership!(project: @project, user: @actor)
      messages = @project.messages.includes(author: :profile).order(:created_at)
      {
        messages: messages.map { |message| serialize(message) },
        unread: unread?(membership),
        messages_last_read_at: membership.messages_last_read_at
      }
    end

    private

    def unread?(membership)
      latest = @project.messages.maximum(:created_at)
      return false if latest.nil?
      return true if membership.messages_last_read_at.nil?

      membership.messages_last_read_at < latest
    end

    def serialize(message)
      {
        id: message.id,
        project_id: message.project_id,
        author_id: message.author_id,
        author_display_name: message.author.profile&.display_name.presence || message.author.email,
        body: message.body,
        created_at: message.created_at
      }
    end
  end
end
