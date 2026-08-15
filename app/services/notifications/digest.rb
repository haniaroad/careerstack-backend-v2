# frozen_string_literal: true

module Notifications
  class Digest
    SEND_START = 8
    SEND_END = 20
    WEEKLY_REMINDER_CAP = 2

    def self.call
      new.call
    end

    def initialize
      @now = Time.current
    end

    def call
      produce_due_reminders
      produce_pending_invitation_reminders
      produce_activity_summaries
      deliver_due_digests
    end

    private

    def produce_due_reminders
      Task.where.not(due_on: nil).where.not(assignee_id: nil).find_each do |task|
        next if task.due_on > Time.find_zone!("UTC").today + 1.day
        next if task.approved?

        user = task.assignee
        next if user.nil?
        next unless under_weekly_cap?(user: user, project: task.project)

        Emit.call(
          event_key: "task_due_reminder",
          actor: nil,
          recipients: [ user ],
          source: task,
          project: task.project,
          payload: {
            "task_title" => task.title.to_s.truncate(30),
            "project_title" => task.project.title.to_s.truncate(30),
            "task_id" => task.id,
            "due_on" => task.due_on.to_s
          }
        )
      end
    end

    def produce_pending_invitation_reminders
      Invitation.where(accepted_at: nil).where(created_at: ..2.days.ago).find_each do |invitation|
        next if invitation.expires_at.present? && invitation.expires_at < Time.current

        user = User.find_by(email: invitation.email)
        Emit.call(
          event_key: "pending_invitation_reminder",
          actor: nil,
          recipients: [ { user: user, email: invitation.email } ],
          source: invitation,
          organization: invitation.organization,
          payload: { "organization_name" => invitation.organization.name }
        )
      end
    end

    def produce_activity_summaries
      User.where(status: User::ACTIVE).find_each do |user|
        NotificationPreference.ensure_defaults!(user)
        preference = user.notification_preferences.find_by(category: "reminders")
        next if preference.nil? || preference.digest_cadence != "weekly"
        next if Notification.for_user(user).where(event_key: "activity_summary", created_at: 7.days.ago..).exists?
        next unless Notification.for_user(user).where(created_at: 7.days.ago..).exists?

        Emit.call(
          event_key: "activity_summary",
          actor: nil,
          recipients: [ user ],
          source: user,
          payload: {}
        )
      end
    end

    def deliver_due_digests
      Notification.where(tier: "digest_config", email_status: "scheduled").includes(:recipient_user).find_each do |notification|
        next unless in_send_window?(notification)

        Deliver.call(notification: notification)
      end
    end

    def in_send_window?(notification)
      zone_name = notification.recipient_user&.timezone.presence || "UTC"
      zone = Time.find_zone(zone_name) || Time.find_zone!("UTC")
      hour = @now.in_time_zone(zone).hour
      hour >= SEND_START && hour < SEND_END
    end

    def under_weekly_cap?(user:, project:)
      return true if project.nil?

      sent = Notification.for_user(user)
                         .where(project: project, tier: "digest_config", email_status: "sent", sent_at: 7.days.ago..)
                         .count
      sent < WEEKLY_REMINDER_CAP
    end
  end
end
