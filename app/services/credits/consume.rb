# frozen_string_literal: true

module Credits
  # Deducts credits FIFO across lots. Idempotent via unique ledger key.
  class Consume
    def self.call(owner:, amount: 1, reason:, idempotency_key:, actor_user: nil, related: nil)
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
        remaining = Balance.remaining(owner: @owner)
        if remaining < @amount
          raise InsufficientCredits.new(
            "Insufficient credits (#{remaining} remaining, #{@amount} required)",
            remaining: remaining
          )
        end

        to_allocate = @amount
        primary_lot = nil

        CreditLot.for_owner(@owner).with_remaining.fifo.lock.to_a.each do |lot|
          break if to_allocate.zero?

          take = [ lot.remaining, to_allocate ].min
          next if take.zero?

          primary_lot ||= lot
          lot.update!(remaining: lot.remaining - take)
          to_allocate -= take
        end

        if to_allocate.positive?
          raise InsufficientCredits.new("Insufficient credits in lots", remaining: 0)
        end

        CreditLedgerEntry.create!(
          owner: @owner,
          event: "consume",
          amount: -@amount,
          actor_user: @actor_user,
          reason: @reason,
          idempotency_key: @idempotency_key,
          credit_lot: primary_lot,
          related: @related
        )
      end.tap do |entry|
        emit_trial_credits_used_up!(entry)
      end
    rescue InsufficientCredits
      emit_not_enough_organization_credits!
      raise
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      existing = CreditLedgerEntry.find_by(idempotency_key: @idempotency_key)
      return existing if existing

      raise e
    end

    private

    def emit_not_enough_organization_credits!
      return unless @owner.is_a?(Organization)

      Notifications::Hook.emit(
        event_key: "not_enough_organization_credits",
        actor: nil,
        recipients: Notifications::Hook.organization_staff(@owner),
        source: Notifications::Hook.named_source("org-credits-insufficient:#{@owner.id}:#{@idempotency_key}"),
        organization: @owner,
        payload: Notifications::Hook.org_payload(@owner)
      )
    end

    def emit_trial_credits_used_up!(entry)
      return unless @owner.is_a?(Organization)
      return unless Balance.remaining(owner: @owner).zero?

      Notifications::Hook.emit(
        event_key: "trial_credits_used_up",
        actor: nil,
        recipients: Notifications::Hook.organization_staff(@owner),
        source: entry,
        organization: @owner,
        payload: Notifications::Hook.org_payload(@owner)
      )
    end
  end
end
