# frozen_string_literal: true

module Notifications
  class Deliver
    SEEN_WINDOW = 15.minutes

    def self.call(notification:, force: false)
      new(notification: notification, force: force).call
    end

    def initialize(notification:, force:)
      @notification = notification
      @force = force
    end

    def call
      return if already_final?

      siblings = coalesced_group
      target = siblings.first || @notification

      if EmailSuppression.suppressed?(target.recipient_email)
        finalize(siblings, status: "suppressed", reason: "suppressed")
        return
      end

      unless @force
        if skip_for_preference?(target)
          finalize(siblings, status: "skipped", reason: "preference")
          return
        end
        if skip_seen?(target)
          finalize(siblings, status: "skipped", reason: "in_app_seen")
          return
        end
      end

      rendered = TransactionalMail::Renderer.call(notification: target, items: siblings)
      reply_to = staff_reply_to?(target) ? Catalog::STAFF_INBOX : nil
      TransactionalMail::Provider.deliver(
        to: target.recipient_email,
        subject: rendered[:subject],
        html: rendered[:html],
        text: rendered[:text],
        reply_to: reply_to
      )
      finalize(siblings, status: "sent")
    rescue StandardError => error
      Rails.logger.error({ event: "notification_deliver_failed", notification_id: @notification.id, error: error.class.name }.to_json)
      @notification.update!(email_status: "failed", email_skip_reason: error.class.name)
    end

    private

    def already_final?
      %w[sent skipped suppressed failed].include?(@notification.email_status)
    end

    def coalesced_group
      return [ @notification ] if @notification.coalesce_key.blank?

      Notification.where(coalesce_key: @notification.coalesce_key, email_status: %w[pending scheduled])
                  .order(:created_at)
                  .to_a
                  .presence || [ @notification ]
    end

    def skip_for_preference?(notification)
      return false if notification.tier == "mandatory"
      return false if notification.recipient_user.nil?

      NotificationPreference.ensure_defaults!(notification.recipient_user)
      meta = Catalog.event!(notification.event_key)
      preference = notification.recipient_user.notification_preferences.find_by(category: meta[:category])
      return false if preference.nil?

      return true unless preference.email_enabled
      return true if preference.digest_cadence == "off"

      false
    end

    def skip_seen?(notification)
      return false if notification.tier == "mandatory"
      return false if notification.read_at.blank?

      notification.read_at <= notification.created_at + SEEN_WINDOW
    end

    def staff_reply_to?(notification)
      %w[escalation_created upgrade_request_received].include?(notification.event_key) &&
        notification.recipient_email == Catalog::STAFF_INBOX
    end

    def finalize(siblings, status:, reason: nil)
      now = Time.current
      siblings.each do |row|
        attrs = { email_status: status, email_skip_reason: reason }
        attrs[:sent_at] = now if status == "sent"
        row.update!(attrs)
      end
    end
  end
end
