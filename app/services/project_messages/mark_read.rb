# frozen_string_literal: true

module ProjectMessages
  class MarkRead
    def self.call(project:, actor:)
      new(project: project, actor: actor).call
    end

    def initialize(project:, actor:)
      @project = project
      @actor = actor
    end

    def call
      membership = Access.membership!(project: @project, user: @actor)
      now = Time.current
      membership.update!(messages_last_read_at: now)
      Notification.for_user(@actor)
                  .where(project_id: @project.id, event_key: "unread_project_messages", read_at: nil)
                  .update_all(read_at: now)
      membership
    end
  end
end
