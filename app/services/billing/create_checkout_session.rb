# frozen_string_literal: true

module Billing
  class CreateCheckoutSession
    def self.call(user:, success_url: nil, cancel_url: nil)
      new(user: user, success_url: success_url, cancel_url: cancel_url).call
    end

    def initialize(user:, success_url:, cancel_url:)
      @user = user
      @success_url = success_url
      @cancel_url = cancel_url
    end

    def call
      raise DomainError.new("Personal purchase is not available", code: "purchase_ineligible") unless eligible?
      raise DomainError.new("Stripe is not configured", code: "billing_misconfigured") unless StripeConfig.configured?

      StripeConfig.apply!
      customer = ensure_customer!
      session = Stripe::Checkout::Session.create(
        mode: "payment",
        customer: customer.stripe_customer_id,
        line_items: [ { price: StripeConfig.price_id, quantity: 1 } ],
        success_url: @success_url.presence || StripeConfig.success_url,
        cancel_url: @cancel_url.presence || StripeConfig.cancel_url,
        client_reference_id: @user.id,
        metadata: {
          careerstack_user_id: @user.id,
          pack: "personal_3_for_20"
        }
      )

      CreditPurchase.create!(
        user: @user,
        stripe_checkout_session_id: session.id,
        status: "pending",
        credits: CreditPurchase::PACK_CREDITS,
        amount_cents: CreditPurchase::PACK_AMOUNT_CENTS
      )

      { checkout_url: session.url, session_id: session.id }
    end

    private

    def eligible?
      @user.adult? && @user.personal_workspace.present? && !@user.pending_onboarding?
    end

    def ensure_customer!
      existing = @user.stripe_customer
      return existing if existing

      stripe_customer = Stripe::Customer.create(
        email: @user.email,
        metadata: { careerstack_user_id: @user.id }
      )
      @user.create_stripe_customer!(stripe_customer_id: stripe_customer.id)
    end
  end
end
