# frozen_string_literal: true

class HomeWarningDismissal < ApplicationRecord
  PHASES = %w[ending_soon grace_period expired].freeze

  belongs_to :user
  belongs_to :project

  validates :phase, inclusion: { in: PHASES }
  validates :dismissed_at, presence: true
  validates :project_id, uniqueness: { scope: [ :user_id, :phase ] }
end
