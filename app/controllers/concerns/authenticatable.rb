# frozen_string_literal: true

module Authenticatable
  extend ActiveSupport::Concern

  PUBLIC_PATHS = %w[/health /ready /up].freeze

  included do
    before_action :require_authentication
  end

  private

  def require_authentication
    return if public_path?
    return if authenticated?

    render_error(
      code: "unauthenticated",
      message: "Authentication required",
      status: :unauthorized
    )
  end

  def public_path?
    PUBLIC_PATHS.include?(request.path)
  end

  # Firebase verification arrives in a later change. Until then, any non-blank
  # Authorization header satisfies the default-deny gate for local/smoke use.
  def authenticated?
    request.headers["Authorization"].to_s.strip.present?
  end
end
