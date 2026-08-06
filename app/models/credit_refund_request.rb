# frozen_string_literal: true

class CreditRefundRequest < ApplicationRecord
  STATUSES = %w[submitted approved denied].freeze

  belongs_to :user
  belongs_to :credit_purchase

  validates :status, inclusion: { in: STATUSES }
  validates :unused_credits_at_request, numericality: { greater_than_or_equal_to: 0 }
end
