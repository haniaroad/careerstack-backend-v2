# frozen_string_literal: true

module ProjectMessages
  class NotifyUnread
    def self.call(message:)
      new(message: message).call
    end

    def initialize(message:)
      @message = message
    end

    def call
      recipients = @message.project.memberships.active.includes(user: :profile).filter_map do |membership|
        next if membership.user_id == @message.author_id
        next if already_read?(membership)

        membership.user
      end
      return if recipients.empty?

      author_name = @message.author.profile&.display_name.presence || "A teammate"
      Notifications::Emit.call(
        event_key: "unread_project_messages",
        actor: @message.author,
        recipients: recipients,
        source: @message,
        project: @message.project,
        payload: {
          "project_title" => @message.project.title.to_s.truncate(30),
          "project_id" => @message.project_id,
          "n" => "1",
          "names" => author_name.to_s.truncate(40)
        }
      )
    end

    private

    def already_read?(membership)
      membership.messages_last_read_at.present? && membership.messages_last_read_at >= @message.created_at
    end
  end
end
