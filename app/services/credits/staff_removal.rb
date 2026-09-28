# frozen_string_literal: true

module Credits
  class StaffRemoval
    def self.call(owner:, amount:, reason:, actor:)
      new(owner: owner, amount: amount, reason: reason, actor: actor).call
    end

    def initialize(owner:, amount:, reason:, actor:)
      @owner = owner
      @amount = amount
      @reason = reason
      @actor = actor
    end

    def call
      available = CreditLot.for_owner(@owner).with_remaining.fifo.sum(:remaining)
      raise DomainError.new("Not enough credits to remove", code: "insufficient_credits") if available < @amount

      key = "staff_remove:#{SecureRandom.uuid}"
      ActiveRecord::Base.transaction do
        remaining = @amount
        CreditLot.for_owner(@owner).with_remaining.fifo.lock.each do |lot|
          break if remaining <= 0

          take = [ lot.remaining, remaining ].min
          lot.update!(remaining: lot.remaining - take)
          remaining -= take
        end

        CreditLedgerEntry.create!(
          owner: @owner,
          event: "staff_removal",
          amount: -@amount,
          actor_user: @actor,
          reason: @reason,
          idempotency_key: key
        )
      end
    end
  end
end
