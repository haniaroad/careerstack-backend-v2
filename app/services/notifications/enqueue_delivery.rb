# frozen_string_literal: true

module Notifications
  class EnqueueDelivery
    COALESCE_WAIT = 10.minutes

    def self.call(notification:)
      new(notification: notification).call
    end

    def initialize(notification:)
      @notification = notification
    end

    def call
      return if %w[sent skipped suppressed failed].include?(@notification.email_status)

      if Catalog.coalescable?(@notification.event_key)
        key = [
          @notification.event_key,
          @notification.project_id,
          @notification.recipient_user_id || @notification.recipient_email
        ].join(":")
        @notification.update!(email_status: "scheduled", coalesce_key: key)
        schedule_or_run(wait: COALESCE_WAIT)
      elsif @notification.tier == "digest_config"
        @notification.update!(email_status: "scheduled")
      else
        schedule_or_run
      end
    end

    private

    def schedule_or_run(wait: nil)
      if inline?
        Deliver.call(notification: @notification.reload) unless wait
        return
      end

      job = Notifications::DeliverJob
      if wait
        job.set(wait: wait).perform_later(@notification.id)
      else
        job.perform_later(@notification.id)
      end
    end

    def inline?
      ENV["EMAIL_INLINE_JOBS"].to_s == "true" || Rails.env.test?
    end
  end
end
