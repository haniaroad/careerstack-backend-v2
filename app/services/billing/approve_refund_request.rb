# frozen_string_literal: true

module Billing
  class ApproveRefundRequest
    def self.call(refund_request:, actor_user: nil)
      new(refund_request: refund_request, actor_user: actor_user).call
    end

    def initialize(refund_request:, actor_user:)
      @refund_request = refund_request
      @actor_user = actor_user
    end

    def call
      raise DomainError.new("Refund request already resolved", code: "refund_ineligible") unless @refund_request.status == "submitted"

      purchase = @refund_request.credit_purchase
      result = Credits::ReverseUnusedPurchase.call(purchase: purchase, actor_user: @actor_user)

      @refund_request.update!(status: "approved", resolved_at: Time.current)
      { refund_request: @refund_request, reversed: result[:reversed] }
    end
  end
end
