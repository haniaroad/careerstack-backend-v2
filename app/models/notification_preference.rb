# frozen_string_literal: true

class NotificationPreference < ApplicationRecord
  CADENCES = %w[realtime daily weekly off].freeze

  belongs_to :user

  validates :category, presence: true
  validates :digest_cadence, inclusion: { in: CADENCES }, allow_nil: true

  def self.ensure_defaults!(user)
    Notifications::Catalog::CATEGORIES.each do |id, meta|
      find_or_create_by!(user: user, category: id) do |row|
        row.email_enabled = meta[:can_disable] ? true : true
        row.digest_cadence = meta[:default_cadence]
      end
    end
  end
end
