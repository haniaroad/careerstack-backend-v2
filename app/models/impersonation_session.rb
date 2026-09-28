# frozen_string_literal: true

class ImpersonationSession < ApplicationRecord
  DURATION = 30.minutes

  belongs_to :actor, class_name: "User"
  belongs_to :target, class_name: "User"

  validates :reason, presence: true

  def expired?
    expires_at <= Time.current
  end

  def active?
    ended_at.nil? && !expired?
  end
end
