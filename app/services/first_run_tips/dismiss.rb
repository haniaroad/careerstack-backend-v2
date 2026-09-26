# frozen_string_literal: true

module FirstRunTips
  class Dismiss
    def self.call(user:, key:)
      new(user:, key:).call
    end

    def initialize(user:, key:)
      @user = user
      @key = key.to_s
    end

    def call
      ensure_onboarded!
      Catalog.entry!(@key)
      dismissal = FirstRunTipDismissal.find_or_initialize_by(user: @user, tip_key: @key)
      dismissal.dismissed_at ||= Time.current
      dismissal.save!
      dismissal
    end

    private

    def ensure_onboarded!
      return unless @user.pending_onboarding?

      raise DomainError.new(
        "Complete onboarding before dismissing tips",
        code: "onboarding_required",
        status: :forbidden
      )
    end
  end
end
