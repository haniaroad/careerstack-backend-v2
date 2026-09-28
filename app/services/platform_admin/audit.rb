# frozen_string_literal: true

module PlatformAdmin
  class Audit
    def self.record!(actor:, action:, target:, reason: nil)
      StaffAuditEvent.create!(
        actor: actor,
        action: action,
        target_type: target.class.name,
        target_id: target.id,
        reason: reason.presence
      )
    end
  end
end
