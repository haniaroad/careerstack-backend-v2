# frozen_string_literal: true

class NotificationSerializer
  def self.list(notifications)
    notifications.map { |notification| call(notification) }
  end

  def self.call(notification)
    payload = notification.payload || {}
    {
      id: notification.id,
      event_key: notification.event_key,
      title: payload["title"] || payload["heading"],
      body: payload["body"],
      path: payload["path"],
      read: notification.read_at.present?,
      created_at: notification.created_at,
      project_id: notification.project_id
    }
  end
end
