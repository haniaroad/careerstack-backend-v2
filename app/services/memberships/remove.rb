# frozen_string_literal: true

module Memberships
  class Remove
    REASONS = %w[
      left_program
      completed_program
      inactive
      policy_violation
      other
    ].freeze

    def self.call(actor:, target:, reason:)
      new(actor: actor, target: target, reason: reason).call
    end

    def initialize(actor:, target:, reason:)
      @actor = actor
      @target = target
      @reason = reason.to_s.strip
    end

    def call
      Organizations::Access.require_writable!(@target.organization)
      raise Error.new("Membership is not active", code: "validation_error") unless @target.active?
      raise Error, "reason is required" if @reason.blank?
      unless REASONS.include?(@reason)
        raise Error, "reason must be one of #{REASONS.join(', ')}"
      end

      if @target.last_administrator?
        raise Error.new(
          "The last active administrator cannot be removed",
          code: "last_administrator"
        )
      end

      workspace = @target.organization.workspace
      ActiveRecord::Base.transaction do
        @target.update!(
          status: OrganizationMembership::STATUS_REMOVED,
          removed_at: Time.current,
          removed_reason: @reason,
          removed_by_user: @actor,
          program_filter_program: nil
        )
        if workspace && @target.user.active_workspace_id == workspace.id
          fallback = @target.user.personal_workspace
          @target.user.update!(active_workspace_id: fallback&.id)
        end
      end
      @target
    end
  end
end
