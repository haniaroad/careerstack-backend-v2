# frozen_string_literal: true

module Credits
  # Grants the single free personal trial credit an adult receives once, ever.
  # Minors and unknown-age users are never eligible; they only become eligible
  # if and when age-up detection flips them to adult.
  class GrantPersonalTrial
    include IdempotentGrant

    AMOUNT = 1
    REASON = "personal_trial"

    def self.call(user:)
      new(user: user).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      return false unless @user.adult?
      return false if @user.personal_trial_granted?

      granted = record_grant(
        owner: @user,
        amount: AMOUNT,
        reason: REASON,
        idempotency_key: self.class.idempotency_key_for(@user),
        actor_user: @user
      )

      # The flag is a denormalized read shortcut; the ledger stays authoritative,
      # so it is set either way once an entry exists for this user.
      @user.update!(personal_trial_granted: true)
      granted
    end

    def self.idempotency_key_for(user)
      "personal_trial:#{user.id}"
    end
  end
end
