# frozen_string_literal: true

module Billing
  class SubmitRefundRequest
    def self.call(user:, purchase:, reason: nil)
      new(user: user, purchase: purchase, reason: reason).call
    end

    def initialize(user:, purchase:, reason:)
      @user = user
      @purchase = purchase
      @reason = reason
    end

    def call
      raise DomainError.new("Purchase not found", code: "not_found", status: :not_found) if @purchase.nil?
      raise DomainError.new("Purchase does not belong to this user", code: "forbidden", status: :forbidden) unless @purchase.user_id == @user.id

      unless @purchase.refund_eligible?
        raise DomainError.new(
          eligibility_message,
          code: "refund_ineligible"
        )
      end

      CreditRefundRequest.create!(
        user: @user,
        credit_purchase: @purchase,
        status: "submitted",
        reason: @reason,
        unused_credits_at_request: @purchase.unused_credits
      )
    end

    private

    def eligibility_message
      return "Purchase is outside the seven-day refund window" unless @purchase.within_refund_window?
      return "No unused credits remain on this purchase" unless @purchase.unused_credits.positive?

      "This purchase is not eligible for a refund"
    end
  end
end
