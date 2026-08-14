# frozen_string_literal: true

module Memberships
  class Update
    ASSIGNABLE = {
      OrganizationMembership::ADMIN => OrganizationMembership::ROLES,
      OrganizationMembership::MANAGER => [ OrganizationMembership::PARTICIPANT ]
    }.freeze

    def self.call(actor_membership:, target:, params:)
      new(actor_membership: actor_membership, target: target, params: params).call
    end

    def initialize(actor_membership:, target:, params:)
      @actor_membership = actor_membership
      @target = target
      @params = params.to_h.with_indifferent_access
    end

    def call
      Organizations::Access.require_writable!(@target.organization)
      raise Error.new("Membership is not active", code: "validation_error") unless @target.active?

      if @params.key?(:role)
        update_role!
      end
      if @params.key?(:program_ids)
        @target.replace_enrollments!(@params[:program_ids])
      end
      @target.reload
    end

    private

    def update_role!
      role = @params[:role].to_s
      unless OrganizationMembership::ROLES.include?(role)
        raise Error, "role must be one of #{OrganizationMembership::ROLES.join(', ')}"
      end

      allowed = ASSIGNABLE.fetch(@actor_membership.role, [])
      unless allowed.include?(role)
        raise Error.new("Your organization role cannot assign #{role}", code: "forbidden", status: :forbidden)
      end

      if @target.administrator? && role != OrganizationMembership::ADMIN && @target.last_administrator?
        raise Error.new(
          "The last active administrator cannot be demoted",
          code: "last_administrator"
        )
      end

      @target.update!(role: role)
    end
  end
end
