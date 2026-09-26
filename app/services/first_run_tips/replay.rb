# frozen_string_literal: true

module FirstRunTips
  class Replay
    def self.call(user:)
      new(user:).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      ensure_onboarded!
      keys = @user.first_run_tip_dismissals.order(:tip_key).pluck(:tip_key)
      @user.first_run_tip_dismissals.delete_all
      keys
    end

    private

    def ensure_onboarded!
      return unless @user.pending_onboarding?

      raise DomainError.new(
        "Complete onboarding before replaying tips",
        code: "onboarding_required",
        status: :forbidden
      )
    end
  end
end
