# frozen_string_literal: true

# Server-issued opaque organization invitation (D-7). Only the SHA-256 digest is
# stored; the raw token is returned exactly once, at creation, and can never be
# recovered from the database.
class Invitation < ApplicationRecord
  DEFAULT_TTL = 14.days
  TOKEN_BYTES = 32

  belongs_to :organization
  belongs_to :program, optional: true
  belongs_to :accepted_by_user, class_name: "User", optional: true
  belongs_to :created_by_user, class_name: "User", optional: true

  validates :token_digest, :expires_at, presence: true
  validates :token_digest, uniqueness: true
  validates :role, inclusion: { in: OrganizationMembership::ROLES }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :pending, -> { where(accepted_at: nil).where(arel_table[:expires_at].gt(Time.current)) }

  class << self
    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token.to_s)
    end

    def find_by_raw_token(raw_token)
      return nil if raw_token.blank?

      find_by(token_digest: digest(raw_token))
    end

    # Returns the persisted invitation plus the raw token for one-time delivery.
    def issue!(organization:, created_by_user: nil, program: nil, email: nil, role: OrganizationMembership::PARTICIPANT, expires_at: DEFAULT_TTL.from_now)
      raw_token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
      invitation = create!(
        organization: organization,
        program: program,
        email: email.presence&.downcase,
        created_by_user: created_by_user,
        role: role,
        expires_at: expires_at,
        token_digest: digest(raw_token)
      )

      [ invitation, raw_token ]
    end
  end

  def expired?
    expires_at <= Time.current
  end

  def accepted?
    accepted_at.present?
  end

  def usable?
    !expired? && !accepted?
  end

  def accept!(user)
    update!(accepted_at: Time.current, accepted_by_user: user)
  end
end
