# frozen_string_literal: true

module Projects
  module JoinEligibility
    module_function

    def assert_can_join!(project:, user:)
      raise DomainError.new("Complete onboarding before joining projects", code: "onboarding_required", status: :forbidden) if user.pending_onboarding?

      workspace = project.workspace
      org_member = workspace.organization_id.present? && user.member_of_workspace?(workspace)
      unless user.adult? || org_member
        raise DomainError.new("Verified adult account required to join", code: "forbidden", status: :forbidden)
      end
      raise DomainError.new("Suspended accounts cannot join projects", code: "forbidden", status: :forbidden) if user.suspended?

      if workspace.organization_id.present?
        unless user.member_of_workspace?(workspace)
          raise DomainError.new("Not a member of this organization workspace", code: "forbidden", status: :forbidden)
        end
      end
    end

    def credit_owner_for_join(project:, user:)
      if project.workspace.organization_id.present?
        project.credit_owner
      else
        user
      end
    end

    def credit_owner_for_membership_restore(project:, membership:)
      if project.workspace.organization_id.present?
        project.credit_owner
      else
        membership.user
      end
    end
  end
end
