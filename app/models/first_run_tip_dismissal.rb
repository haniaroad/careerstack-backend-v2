# frozen_string_literal: true

class FirstRunTipDismissal < ApplicationRecord
  belongs_to :user

  validates :tip_key, inclusion: { in: FirstRunTips::Catalog::KEYS }
  validates :tip_key, uniqueness: { scope: :user_id }
  validates :dismissed_at, presence: true
end
