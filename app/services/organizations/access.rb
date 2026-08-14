# frozen_string_literal: true

module Organizations
  class Access
    Result = Struct.new(:organization, :membership, keyword_init: true)

    def self.staff!(user:, organization_id:)
      organization = Organization.find(organization_id)
      membership = user.membership_for(organization)
      unless membership&.staff?
        raise Error.new(
          "Organization administrator access is required",
          code: "forbidden",
          status: :forbidden
        )
      end

      unless user.resolved_active_workspace&.organization_id == organization.id
        raise Error.new(
          "Switch to this organization workspace first",
          code: "forbidden",
          status: :forbidden
        )
      end

      Result.new(organization: organization, membership: membership)
    end

    def self.admin!(user:, organization_id:)
      result = staff!(user: user, organization_id: organization_id)
      unless result.membership.administrator?
        raise Error.new(
          "Only organization administrators can perform this action",
          code: "forbidden",
          status: :forbidden
        )
      end
      result
    end

    def self.require_writable!(organization)
      return if organization.writable?

      message = organization.workspace_disabled? ?
        "This organization workspace is disabled" :
        "This organization is read-only during offboarding"
      raise Error.new(message, code: "organization_read_only")
    end
  end
end
