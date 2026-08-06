# frozen_string_literal: true

module Credits
  # Reverses unused credits on an approved personal pack purchase.
  # Used credits on the purchase lot are never reversed.
  class ReverseUnusedPurchase
    def self.call(purchase:, actor_user: nil)
      new(purchase: purchase, actor_user: actor_user).call
    end

    def initialize(purchase:, actor_user:)
      @purchase = purchase
      @actor_user = actor_user
    end

    def call
      lot = @purchase.credit_lot
      raise DomainError.new("Purchase has no credit lot", code: "refund_ineligible") if lot.nil?

      unused = lot.remaining
      raise DomainError.new("No unused credits remain on this purchase", code: "refund_ineligible") if unused <= 0

      idempotency_key = "refund_reverse:#{@purchase.id}"
      existing = CreditLedgerEntry.find_by(idempotency_key: idempotency_key)
      return { entry: existing, reversed: 0 } if existing

      ActiveRecord::Base.transaction do
        lot.lock!
        unused = lot.remaining
        raise DomainError.new("No unused credits remain on this purchase", code: "refund_ineligible") if unused <= 0

        lot.update!(remaining: 0)

        entry = CreditLedgerEntry.create!(
          owner: lot.owner,
          event: "refund_reversal",
          amount: -unused,
          actor_user: @actor_user,
          reason: "unused_credit_refund",
          idempotency_key: idempotency_key,
          credit_lot: lot,
          related: @purchase
        )

        { entry: entry, reversed: unused }
      end
    end
  end
end
