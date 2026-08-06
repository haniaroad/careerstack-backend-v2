# frozen_string_literal: true

module Credits
  class History
    def self.call(owner:, limit: 50)
      CreditLedgerEntry
        .where(owner: owner)
        .includes(:credit_lot)
        .order(created_at: :desc)
        .limit(limit)
        .map { |entry| serialize(entry) }
    end

    def self.serialize(entry)
      {
        id: entry.id,
        event: entry.event,
        reason: entry.reason,
        amount: entry.amount,
        related_type: entry.related_type,
        related_id: entry.related_id,
        credit_lot_id: entry.credit_lot_id,
        lot_source: entry.credit_lot&.source,
        created_at: entry.created_at
      }
    end
    private_class_method :serialize
  end
end
