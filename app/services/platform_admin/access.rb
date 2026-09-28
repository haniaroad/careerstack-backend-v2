# frozen_string_literal: true

module PlatformAdmin
  class Access
    SESSION_TTL = 8.hours
    REAUTH_WINDOW = 5.minutes

    def self.authorize!(user:, identity:)
      new(user: user, identity: identity).authorize!
    end

    def self.reauthenticated?(identity)
      identity&.auth_time.present? && identity.auth_time >= REAUTH_WINDOW.ago
    end

    def initialize(user:, identity:)
      @user = user
      @identity = identity
    end

    def authorize!
      raise DomainError.new("Platform admin access is required", code: "forbidden", status: :forbidden) unless allowed?
      raise DomainError.new("Staff session expired", code: "staff_session_expired", status: :unauthorized) if session_expired?

      true
    end

    def allowed?
      @identity&.platform_admin && @user&.platform_admin?
    end

    def session_expired?
      return false if @identity&.auth_time.blank?

      @identity.auth_time < SESSION_TTL.ago
    end
  end
end
