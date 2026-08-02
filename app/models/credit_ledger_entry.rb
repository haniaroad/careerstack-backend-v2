# frozen_string_literal: true

class CreditLedgerEntry < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :actor_user, class_name: "User", optional: true

  validates :event, :reason, :idempotency_key, presence: true
  validates :amount, numericality: { other_than: 0 }
  validates :idempotency_key, uniqueness: true
end
