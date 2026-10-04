# frozen_string_literal: true

module Projects
  module Editor
    module_function

    # Creators may edit their own projects. Organization admins and managers
    # may edit active projects in their organization. Personal projects stay
    # creator-only.
    def allowed?(project:, user:)
      return false unless user.member_of_workspace?(project.workspace)
      return true if project.creator_id == user.id

      project.workspace.organization? && user.can_access_org_admin_for?(project.workspace)
    end
  end
end
