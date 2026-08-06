# frozen_string_literal: true

module Api
  module V1
    module Billing
      class RefundRequestsController < BaseController
        def create
          purchase = current_user.credit_purchases.find(params.require(:purchase_id))
          request_record = ::Billing::SubmitRefundRequest.call(
            user: current_user,
            purchase: purchase,
            reason: params[:reason]
          )
          render json: {
            refund_request: {
              id: request_record.id,
              status: request_record.status,
              purchase_id: request_record.credit_purchase_id,
              unused_credits_at_request: request_record.unused_credits_at_request,
              created_at: request_record.created_at
            }
          }, status: :created
        end
      end
    end
  end
end
