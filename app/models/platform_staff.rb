# frozen_string_literal: true

class PlatformStaff < ApplicationRecord
  self.table_name = "platform_staff"

  ROLE = "platform_admin"

  belongs_to :user

  validates :role, inclusion: { in: [ ROLE ] }

  scope :active, -> { where(active: true) }

  def active_admin?
    active? && role == ROLE
  end
end
