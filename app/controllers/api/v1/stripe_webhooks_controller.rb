# frozen_string_literal: true

module Api
  module V1
    # Stripe webhook ingress — public for Firebase auth, signature-verified.
    class StripeWebhooksController < BaseController
      skip_before_action :require_authentication

      def create
        result = ::Billing::ProcessWebhook.call(
          payload: request.body.read,
          signature: request.env["HTTP_STRIPE_SIGNATURE"]
        )
        render json: result, status: :ok
      end
    end
  end
end
