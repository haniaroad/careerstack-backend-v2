# frozen_string_literal: true

module Credits
  # Shared append-only ledger write for grants (D-5 / credit lots).
  #
  # The unique index on idempotency_key is the real guard against double grants.
  # The insert runs in its own savepoint because these grants are called from
  # inside the onboarding transaction: without one, a unique violation would
  # abort the whole enclosing transaction instead of just the duplicate insert.
  module IdempotentGrant
    private

    def record_grant(owner:, amount:, reason:, idempotency_key:, actor_user:, stripe_payment_ref: nil, source: nil)
      return false if CreditLedgerEntry.exists?(idempotency_key: idempotency_key)

      lot_source = source || reason

      ActiveRecord::Base.transaction(requires_new: true) do
        lot = CreditLot.create!(
          owner: owner,
          source: lot_source,
          original_amount: amount,
          remaining: amount,
          stripe_payment_ref: stripe_payment_ref,
          granted_at: Time.current
        )

        CreditLedgerEntry.create!(
          owner: owner,
          event: "grant",
          amount: amount,
          actor_user: actor_user,
          reason: reason,
          idempotency_key: idempotency_key,
          credit_lot: lot
        )
      end

      true
    rescue ActiveRecord::RecordNotUnique
      false
    rescue ActiveRecord::RecordInvalid => e
      # A concurrent grant landed between the existence check and the insert.
      raise unless e.record.errors.of_kind?(:idempotency_key, :taken)

      false
    end
  end
end
