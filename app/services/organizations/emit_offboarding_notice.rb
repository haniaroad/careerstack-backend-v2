# frozen_string_literal: true

module Organizations
  class EmitOffboardingNotice
    NOTICE_DAYS = [ 30, 14, 7, 1 ].freeze

    def self.call(organization:, days_remaining:)
      new(organization: organization, days_remaining: days_remaining).call
    end

    def initialize(organization:, days_remaining:)
      @organization = organization
      @days_remaining = days_remaining.to_i
    end

    def call
      return unless NOTICE_DAYS.include?(@days_remaining)

      Notifications::Hook.emit(
        event_key: "organization_offboarding",
        actor: nil,
        recipients: Notifications::Hook.organization_members(@organization),
        source: Notifications::Hook.named_source("org-offboard:#{@organization.id}:#{@days_remaining}"),
        organization: @organization,
        payload: Notifications::Hook.org_payload(@organization, "days_remaining" => @days_remaining)
      )
    end
  end
end
