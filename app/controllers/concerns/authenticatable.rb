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
    before_action :enforce_impersonation_policy
  end

  private

  attr_reader :current_user, :current_identity, :impersonation_session

  def require_authentication
    return if public_path?

    identity = FirebaseTokenVerifier.verify!(request.headers["Authorization"])
    @current_identity = identity
    @current_user = resolve_user!(identity)
    @impersonation_session = load_impersonation_session

    deny_suspended_account if @current_user.suspended?
    deny_deletion_recovery if @current_user.in_deletion_recovery?
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

  def deny_deletion_recovery
    render_error(
      code: "account_deletion_recovery",
      message: "This account is in deletion recovery and cannot use the application",
      status: :forbidden
    )
  end

  def load_impersonation_session
    session_id = request.headers["X-Impersonation-Session"].to_s
    return nil if session_id.blank? || @current_user.nil?

    session = ImpersonationSession.find_by(id: session_id, actor_id: @current_user.id)
    return nil if session.nil?
    if session.ended_at.nil? && session.expired?
      session.update!(ended_at: Time.current)
      PlatformAdmin::Audit.record!(actor: @current_user, action: "impersonation_expire", target: session, reason: "expired")
      return nil
    end
    return nil unless session.active?

    session
  end

  def enforce_impersonation_policy
    return if performed?
    return if impersonation_session.nil?

    if request.path.include?("date_of_birth") || request.path.include?("files/")
      render_error(code: "impersonation_read_only", message: "Impersonation cannot access this resource", status: :forbidden)
      return
    end

    return if request.get? || request.head?
    return if request.post? && request.path.match?(%r{/platform_admin/impersonation/[^/]+/exit\z})

    render_error(
      code: "impersonation_read_only",
      message: "Impersonation is read-only",
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
