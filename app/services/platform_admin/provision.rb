# frozen_string_literal: true

module PlatformAdmin
  class Provision
    def self.call(email:, active:, actor: nil)
      new(email: email, active: active, actor: actor).call
    end

    def initialize(email:, active:, actor:)
      @email = email.to_s.strip.downcase
      @active = active
      @actor = actor
    end

    def call
      user = User.find_by!(email: @email)
      staff = PlatformStaff.find_or_initialize_by(user: user)
      staff.role = PlatformStaff::ROLE
      staff.active = @active
      staff.save!
      Claims.sync!(user: user, enabled: @active)
      auditor = @actor || user
      Audit.record!(actor: auditor, action: @active ? "staff_provision" : "staff_deactivate", target: staff, reason: "operator")
      staff
    end
  end
end
