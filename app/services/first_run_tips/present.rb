# frozen_string_literal: true

module FirstRunTips
  class Present
    def self.call(user:, destination:)
      new(user:, destination:).call
    end

    def initialize(user:, destination:)
      @user = user
      @destination = destination.to_s
    end

    def call
      ensure_onboarded!
      entry = Catalog.entry!(@destination)
      return nil if FirstRunTipDismissal.exists?(user_id: @user.id, tip_key: @destination)

      {
        key: @destination,
        label: entry[:label],
        body: Catalog.restricted?(@user, @destination) ? entry[:restricted] : entry[:standard]
      }
    end

    private

    def ensure_onboarded!
      return unless @user.pending_onboarding?

      raise DomainError.new(
        "Complete onboarding before viewing tips",
        code: "onboarding_required",
        status: :forbidden
      )
    end
  end
end
