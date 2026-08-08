# frozen_string_literal: true

class ProjectApplication < ApplicationRecord
  STATUS_PENDING = "pending"
  STATUS_APPROVED = "approved"
  STATUS_REJECTED = "rejected"
  STATUS_EXPIRED = "expired"
  STATUSES = [ STATUS_PENDING, STATUS_APPROVED, STATUS_REJECTED, STATUS_EXPIRED ].freeze

  belongs_to :project
  belongs_to :applicant, class_name: "User"
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :requested_role, presence: true, length: { maximum: 120 }
  validates :motivation, presence: true, length: { maximum: 2000 }
  validates :availability_confirmed, inclusion: { in: [ true ] }, on: :create
  validates :status, inclusion: { in: STATUSES }
  validate :optional_urls_are_https

  scope :pending, -> { where(status: STATUS_PENDING) }

  def pending?
    status == STATUS_PENDING
  end

  private

  def optional_urls_are_https
    %i[portfolio_url github_url resume_url].each do |field|
      value = public_send(field)
      next if value.blank?

      uri = URI.parse(value)
      next if uri.is_a?(URI::HTTPS) && uri.host.present?

      errors.add(field, "must be a valid https:// URL")
    rescue URI::InvalidURIError
      errors.add(field, "must be a valid https:// URL")
    end
  end
end
