# frozen_string_literal: true

module Billing
  class ReconcilePurchases
    def self.call
      new.call
    end

    def call
      mismatches = []

      CreditPurchase.where(status: "completed").find_each do |purchase|
        if purchase.credit_lot.nil?
          mismatches << { purchase_id: purchase.id, issue: "missing_lot" }
          next
        end

        grant = CreditLedgerEntry.find_by(
          owner: purchase.user,
          reason: "personal_pack_purchase",
          credit_lot_id: purchase.credit_lot_id,
          event: "grant"
        )
        mismatches << { purchase_id: purchase.id, issue: "missing_grant" } if grant.nil?
      end

      pending_stale = CreditPurchase.where(status: "pending").where("created_at < ?", 2.days.ago)
      pending_stale.find_each do |purchase|
        mismatches << { purchase_id: purchase.id, issue: "stale_pending" }
      end

      Rails.logger.warn({ event: "billing.reconcile", mismatch_count: mismatches.size, mismatches: mismatches }.to_json) if mismatches.any?
      mismatches
    end
  end
end
