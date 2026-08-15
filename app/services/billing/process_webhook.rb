# frozen_string_literal: true

module Billing
  class ProcessWebhook
    include Credits::IdempotentGrant

    def self.call(payload:, signature:)
      new(payload: payload, signature: signature).call
    end

    def initialize(payload:, signature:)
      @payload = payload
      @signature = signature
    end

    def call
      raise DomainError.new("Stripe webhook is not configured", code: "billing_misconfigured", status: :service_unavailable) unless StripeConfig.webhook_configured?

      event = construct_event!
      return { status: :already_processed } if StripeWebhookEvent.exists?(stripe_event_id: event.id)

      ActiveRecord::Base.transaction do
        StripeWebhookEvent.create!(
          stripe_event_id: event.id,
          event_type: event.type,
          processing_status: "processed"
        )
        handle(event)
      end

      { status: :processed, event_type: event.type }
    rescue Stripe::SignatureVerificationError
      raise DomainError.new("Invalid Stripe signature", code: "invalid_stripe_signature", status: :bad_request)
    end

    private

    def construct_event!
      Stripe::Webhook.construct_event(@payload, @signature, StripeConfig.webhook_secret)
    end

    def handle(event)
      case event.type
      when "checkout.session.completed"
        complete_checkout!(event.data.object, event.id)
      when "checkout.session.expired"
        mark_purchase_status!(event.data.object.id, "expired")
      when "checkout.session.async_payment_failed"
        mark_purchase_status!(event.data.object.id, "cancelled")
      end
    end

    def complete_checkout!(session, event_id)
      user_id = session.metadata&.[]("careerstack_user_id") || session.client_reference_id
      raise DomainError.new("Checkout session missing CareerStack user", code: "webhook_invalid") if user_id.blank?

      user = User.find(user_id)
      purchase = CreditPurchase.find_or_initialize_by(stripe_checkout_session_id: session.id)
      purchase.user ||= user
      purchase.credits ||= CreditPurchase::PACK_CREDITS
      purchase.amount_cents ||= CreditPurchase::PACK_AMOUNT_CENTS

      return if purchase.completed?

      payment_ref = session.payment_intent.presence || session.id
      granted = record_grant(
        owner: user,
        amount: CreditPurchase::PACK_CREDITS,
        reason: "personal_pack_purchase",
        source: "personal_pack_purchase",
        idempotency_key: "stripe_event:#{event_id}",
        actor_user: user,
        stripe_payment_ref: payment_ref.to_s
      )

      lot = CreditLot.find_by!(stripe_payment_ref: payment_ref.to_s) if granted
      lot ||= CreditLot.for_owner(user).where(source: "personal_pack_purchase").order(created_at: :desc).first

      purchase.assign_attributes(
        status: "completed",
        stripe_payment_intent_id: session.payment_intent,
        credit_lot: lot,
        completed_at: Time.current
      )
      purchase.save!

      Notifications::Hook.emit(
        event_key: "purchase_receipt",
        actor: nil,
        recipients: [ user ],
        source: purchase,
        payload: {}
      )
    end

    def mark_purchase_status!(session_id, status)
      purchase = CreditPurchase.find_by(stripe_checkout_session_id: session_id)
      return if purchase.nil? || purchase.completed?

      purchase.update!(status: status)
    end
  end
end
