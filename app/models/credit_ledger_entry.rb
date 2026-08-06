# frozen_string_literal: true

class CreditLedgerEntry < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :actor_user, class_name: "User", optional: true
  belongs_to :credit_lot, optional: true
  belongs_to :related, polymorphic: true, optional: true

  validates :event, :reason, :idempotency_key, presence: true
  validates :amount, numericality: { other_than: 0 }
  validates :idempotency_key, uniqueness: true
end
