# frozen_string_literal: true

module Credits
  # Restores one credit on project cancellation for an eligible member.
  # Leave/remove must not call this.
  class Restore
    def self.call(owner:, amount: 1, reason: "cancellation_restore", idempotency_key:, actor_user: nil, related: nil)
      new(
        owner: owner,
        amount: amount,
        reason: reason,
        idempotency_key: idempotency_key,
        actor_user: actor_user,
        related: related
      ).call
    end

    def initialize(owner:, amount:, reason:, idempotency_key:, actor_user:, related:)
      @owner = owner
      @amount = amount
      @reason = reason
      @idempotency_key = idempotency_key
      @actor_user = actor_user
      @related = related
    end

    def call
      raise ArgumentError, "amount must be positive" unless @amount.positive?

      existing = CreditLedgerEntry.find_by(idempotency_key: @idempotency_key)
      return existing if existing

      ActiveRecord::Base.transaction do
        lot = CreditLot.create!(
          owner: @owner,
          source: "cancellation_restore",
          original_amount: @amount,
          remaining: @amount,
          granted_at: Time.current
        )

        CreditLedgerEntry.create!(
          owner: @owner,
          event: "restore",
          amount: @amount,
          actor_user: @actor_user,
          reason: @reason,
          idempotency_key: @idempotency_key,
          credit_lot: lot,
          related: @related
        )
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      existing = CreditLedgerEntry.find_by(idempotency_key: @idempotency_key)
      return existing if existing

      raise e
    end
  end
end
