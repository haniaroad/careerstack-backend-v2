# frozen_string_literal: true

class EmailSuppression < ApplicationRecord
  REASONS = %w[bounce complaint].freeze

  validates :address, presence: true, uniqueness: { case_sensitive: false }
  validates :reason, inclusion: { in: REASONS }
  validates :occurred_at, presence: true

  before_validation { self.address = address.to_s.strip.downcase }

  def self.suppressed?(email)
    exists?(address: email.to_s.strip.downcase)
  end
end
