# frozen_string_literal: true

module Profiles
  # Projects for profile presentation: full summary for personal / public-safe
  # work, accomplishment-only for private organization work on public DTOs.
  class ProjectSummaries
    def self.call(user:, public_view:)
      new(user: user, public_view: public_view).as_json
    end

    def initialize(user:, public_view:)
      @user = user
      @public_view = public_view
    end

    def as_json
      memberships = ProjectMembership.active
                                     .includes(project: { workspace: :organization })
                                     .where(user_id: @user.id)
                                     .order(created_at: :desc)

      memberships.filter_map do |membership|
        project = membership.project
        next if project.draft? || project.cancelled?

        private_org = project.workspace.organization_id.present?
        if @public_view && private_org
          accomplishment_summary(project, membership)
        else
          full_summary(project, membership, private_org: private_org)
        end
      end
    end

    private

    def accomplishment_summary(project, membership)
      {
        kind: "accomplishment_summary",
        project_id: project.id,
        title: project.title,
        organization_name: project.workspace.organization&.name,
        status: project.status,
        role: membership.role,
        skills: Array(project.skills),
        contribution_stats: {
          tasks_approved: Task.where(project_id: project.id, assignee_id: @user.id, status: Task::STATUS_APPROVED).count
        }
      }
    end

    def full_summary(project, membership, private_org:)
      {
        kind: private_org ? "organization_project" : "personal_project",
        project_id: project.id,
        title: project.title,
        summary: project.summary,
        status: project.status,
        mode: project.mode,
        role: membership.role,
        skills: Array(project.skills),
        organization_name: project.workspace.organization&.name,
        ends_on: project.ends_on,
        phase: project.phase
      }
    end
  end
end
