# frozen_string_literal: true

class CreditPurchase < ApplicationRecord
  STATUSES = %w[pending completed expired cancelled].freeze
  PACK_CREDITS = 3
  PACK_AMOUNT_CENTS = 2000

  belongs_to :user
  belongs_to :credit_lot, optional: true
  has_many :credit_refund_requests, dependent: :restrict_with_exception

  validates :stripe_checkout_session_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :credits, numericality: { greater_than: 0 }

  def completed?
    status == "completed"
  end

  def within_refund_window?(as_of: Time.current)
    completed_at.present? && completed_at >= 7.days.ago(as_of)
  end

  def unused_credits
    credit_lot&.remaining.to_i
  end

  def refund_eligible?(as_of: Time.current)
    completed? && within_refund_window?(as_of: as_of) && unused_credits.positive?
  end
end
