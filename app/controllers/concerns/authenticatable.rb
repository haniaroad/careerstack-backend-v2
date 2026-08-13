# frozen_string_literal: true

# Default-deny authentication. Every request outside PUBLIC_PATHS must present a
# verified Firebase ID token; the first verified token for an email bootstraps a
# local User in pending_onboarding (D-3).
module Authenticatable
  extend ActiveSupport::Concern

  PUBLIC_PATHS = %w[/health /ready /up /api/v1/stripe/webhooks].freeze
  PUBLIC_PATH_PREFIXES = %w[/api/v1/public/].freeze

  included do
    before_action :require_authentication
  end

  private

  attr_reader :current_user

  def require_authentication
    return if public_path?

    identity = FirebaseTokenVerifier.verify!(request.headers["Authorization"])
    @current_user = resolve_user!(identity)

    deny_suspended_account if @current_user.suspended?
  rescue FirebaseTokenVerifier::VerificationError
    render_error(code: "unauthenticated", message: "Authentication required", status: :unauthorized)
  end

  def public_path?
    return true if PUBLIC_PATHS.include?(request.path)

    PUBLIC_PATH_PREFIXES.any? { |prefix| request.path.start_with?(prefix) }
  end

  def deny_suspended_account
    render_error(
      code: "account_suspended",
      message: "This account is suspended and cannot use the application",
      status: :forbidden
    )
  end

  # One CareerStack account per verified email (D-2). A provider re-link keeps
  # the account and updates the stored firebase_uid.
  def resolve_user!(identity)
    user = User.find_by(firebase_uid: identity.firebase_uid) || User.find_by(email: identity.email)
    return sync_identity!(user, identity) if user

    User.create!(
      firebase_uid: identity.firebase_uid,
      email: identity.email,
      status: "pending_onboarding"
    )
  rescue ActiveRecord::RecordNotUnique
    # A concurrent first request for the same identity won the insert.
    User.find_by!(firebase_uid: identity.firebase_uid)
  end

  def sync_identity!(user, identity)
    changes = {}
    changes[:firebase_uid] = identity.firebase_uid if user.firebase_uid != identity.firebase_uid
    changes[:email] = identity.email if user.email != identity.email
    user.update!(changes) if changes.any?
    user
  end
end
