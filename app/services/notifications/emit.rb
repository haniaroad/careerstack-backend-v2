# frozen_string_literal: true

module Notifications
  class Emit
    def self.call(event_key:, actor:, recipients:, source:, payload: {}, project: nil, organization: nil)
      new(
        event_key: event_key,
        actor: actor,
        recipients: recipients,
        source: source,
        payload: payload,
        project: project,
        organization: organization
      ).call
    end

    def initialize(event_key:, actor:, recipients:, source:, payload:, project:, organization:)
      @event_key = event_key.to_s
      @actor = actor
      @recipients = Array(recipients)
      @source = source
      @payload = (payload || {}).stringify_keys
      @project = project
      @organization = organization
    end

    def call
      meta = Catalog.event!(@event_key)
      return [] unless meta[:emit]

      copy = Catalog.copy_for(@event_key)
      created = []

      @recipients.each do |recipient|
        user, email = normalize_recipient(recipient)
        next if email.blank?
        next if @actor && user && user.id == @actor.id

        attributes = {
          recipient_user: user,
          recipient_email: email,
          event_key: @event_key,
          tier: meta[:tier],
          source_type: @source.class.name,
          source_id: @source.id,
          project: @project,
          organization: @organization,
          actor: @actor,
          payload: payload_for(copy, user)
        }

        notification = insert_idempotent(attributes)
        next if notification.nil?

        EnqueueDelivery.call(notification: notification)
        created << notification
      end

      created
    rescue ArgumentError
      raise
    rescue StandardError => error
      Rails.logger.error({ event: "notification_emit_failed", event_key: @event_key, error: error.class.name }.to_json)
      []
    end

    private

    def normalize_recipient(recipient)
      case recipient
      when User
        [ recipient, recipient.email ]
      when Hash
        user = recipient[:user] || recipient["user"]
        email = recipient[:email] || recipient["email"] || user&.email
        [ user, email.to_s.strip.downcase ]
      else
        [ nil, recipient.to_s.strip.downcase ]
      end
    end

    def payload_for(copy, user)
      data = @payload.merge(
        "title" => Catalog.interpolate(copy[:title], @payload),
        "heading" => Catalog.interpolate(copy[:heading], @payload),
        "body" => Catalog.interpolate(copy[:body], @payload),
        "cta" => copy[:cta],
        "path" => Catalog.interpolate(copy[:path], @payload)
      )
      data["recipient_user_id"] = user.id if user
      data
    end

    def insert_idempotent(attributes)
      ActiveRecord::Base.transaction(requires_new: true) do
        Notification.create!(attributes)
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
