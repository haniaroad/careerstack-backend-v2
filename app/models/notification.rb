# frozen_string_literal: true

class Notification < ApplicationRecord
  TIERS = %w[mandatory realtime_config digest_config].freeze
  EMAIL_STATUSES = %w[pending scheduled sent skipped suppressed failed].freeze

  belongs_to :recipient_user, class_name: "User", optional: true
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :project, optional: true
  belongs_to :organization, optional: true

  validates :recipient_email, presence: true
  validates :event_key, presence: true
  validates :tier, inclusion: { in: TIERS }
  validates :source_type, :source_id, presence: true
  validates :email_status, inclusion: { in: EMAIL_STATUSES }

  scope :for_user, ->(user) { where(recipient_user_id: user.id) }
  scope :unread, -> { where(read_at: nil) }
  scope :in_app, -> { where.not(recipient_user_id: nil) }

  def unread?
    read_at.nil?
  end

  def mark_read!
    update!(read_at: Time.current) if read_at.nil?
  end
end
