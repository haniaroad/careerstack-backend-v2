# frozen_string_literal: true

class CreditLot < ApplicationRecord
  SOURCES = %w[
    personal_trial
    organization_trial
    personal_pack_purchase
    organization_contract
    cancellation_restore
  ].freeze

  belongs_to :owner, polymorphic: true
  has_many :credit_ledger_entries, dependent: :nullify
  has_one :credit_purchase, dependent: :nullify

  validates :source, inclusion: { in: SOURCES }
  validates :original_amount, numericality: { greater_than: 0 }
  validates :remaining, numericality: { greater_than_or_equal_to: 0 }
  validate :remaining_not_above_original

  scope :with_remaining, -> { where("remaining > 0") }
  scope :fifo, -> { order(granted_at: :asc, created_at: :asc) }
  scope :for_owner, ->(owner) { where(owner: owner) }

  def purchased?
    source == "personal_pack_purchase"
  end

  def trial?
    source.in?(%w[personal_trial organization_trial])
  end

  private

  def remaining_not_above_original
    return if remaining.blank? || original_amount.blank?
    return if remaining <= original_amount

    errors.add(:remaining, "cannot exceed original_amount")
  end
end
