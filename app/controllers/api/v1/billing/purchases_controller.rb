# frozen_string_literal: true

module Api
  module V1
    module Billing
      class PurchasesController < BaseController
        def index
          purchases = current_user.credit_purchases.order(created_at: :desc).limit(50)
          render json: {
            purchases: purchases.map { |purchase| serialize_purchase(purchase).merge(
              refund_eligible: purchase.refund_eligible?,
              unused_credits: purchase.unused_credits,
              within_refund_window: purchase.within_refund_window?
            ) }
          }
        end

        def show
          purchase = current_user.credit_purchases.find(params[:id])
          render json: {
            purchase: serialize_purchase(purchase).merge(
              refund_eligible: purchase.refund_eligible?,
              unused_credits: purchase.unused_credits,
              within_refund_window: purchase.within_refund_window?
            )
          }
        end

        private

        def serialize_purchase(purchase)
          {
            id: purchase.id,
            status: purchase.status,
            credits: purchase.credits,
            amount_cents: purchase.amount_cents,
            currency: purchase.currency,
            stripe_checkout_session_id: purchase.stripe_checkout_session_id,
            completed_at: purchase.completed_at,
            created_at: purchase.created_at
          }
        end
      end
    end
  end
end
