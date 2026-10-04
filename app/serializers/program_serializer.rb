# frozen_string_literal: true

class ProgramSerializer
  def self.call(program)
    {
      id: program.id,
      organization_id: program.organization_id,
      name: program.name,
      description: program.description,
      status: program.status,
      member_count: program.program_enrollments.joins(:organization_membership).merge(OrganizationMembership.active).count,
      active_project_count: program.projects.where(status: Project::STATUS_ACTIVE).count,
      completed_project_count: program.projects.where(status: Project::STATUS_COMPLETED).count,
      pending_invitation_count: program.invitations.pending.count,
      projects: program.projects.order(:title).map { |project| program_project(project) },
      can_delete: program.draft? && program.empty_for_delete?,
      can_archive: !program.archived?,
      read_only: program.archived?,
      created_at: program.created_at,
      updated_at: program.updated_at
    }
  end

  def self.program_project(project)
    {
      id: project.id,
      title: project.title,
      status: project.status
    }
  end
end
