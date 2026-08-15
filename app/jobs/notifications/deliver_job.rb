# frozen_string_literal: true

module Notifications
  class DeliverJob < ApplicationJob
    queue_as :mailers

    def perform(notification_id)
      notification = Notification.find_by(id: notification_id)
      return if notification.nil?

      Deliver.call(notification: notification)
    end
  end
end
