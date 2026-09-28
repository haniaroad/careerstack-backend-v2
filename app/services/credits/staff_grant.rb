# frozen_string_literal: true

module Credits
  class StaffGrant
    include IdempotentGrant

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
      record_grant(
        owner: @owner,
        amount: @amount,
        reason: @reason,
        idempotency_key: "staff_grant:#{SecureRandom.uuid}",
        actor_user: @actor,
        source: "staff_grant"
      )
    end
  end
end
