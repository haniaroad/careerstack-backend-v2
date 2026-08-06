# frozen_string_literal: true

module Credits
  class Balance
    def self.remaining(owner:)
      CreditLedgerEntry.where(owner: owner).sum(:amount)
    end

    def self.summary(owner:)
      remaining = remaining(owner: owner)
      lots = CreditLot.for_owner(owner).with_remaining.fifo.to_a
      trial_remaining = lots.select(&:trial?).sum(&:remaining)
      purchased_remaining = lots.select(&:purchased?).sum(&:remaining)

      {
        remaining: remaining,
        trial_remaining: trial_remaining,
        purchased_remaining: purchased_remaining,
        owner_type: owner.class.name.underscore
      }
    end
  end
end
