# frozen_string_literal: true

module Billing
  module StripeConfig
    module_function

    def secret_key
      ENV.fetch("STRIPE_SECRET_KEY", "")
    end

    def webhook_secret
      ENV.fetch("STRIPE_WEBHOOK_SECRET", "")
    end

    def price_id
      ENV.fetch("STRIPE_PERSONAL_PACK_PRICE_ID", "")
    end

    def success_url
      ENV.fetch("STRIPE_CHECKOUT_SUCCESS_URL", "http://localhost:5173/billing/return?status=success&session_id={CHECKOUT_SESSION_ID}")
    end

    def cancel_url
      ENV.fetch("STRIPE_CHECKOUT_CANCEL_URL", "http://localhost:5173/billing/return?status=cancelled")
    end

    def configured?
      secret_key.present? && price_id.present?
    end

    def webhook_configured?
      secret_key.present? && webhook_secret.present?
    end

    def apply!
      Stripe.api_key = secret_key if secret_key.present?
    end
  end
end
