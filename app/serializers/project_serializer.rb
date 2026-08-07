# frozen_string_literal: true

class ProjectSerializer
  def self.call(project)
    new(project).as_json
  end

  def initialize(project)
    @project = project
  end

  def as_json
    {
      id: @project.id,
      title: @project.title,
      summary: @project.summary,
      skills: @project.skills,
      mode: @project.mode,
      status: @project.status,
      workspace_id: @project.workspace_id,
      creator_id: @project.creator_id,
      confirmed_at: @project.confirmed_at,
      cancelled_at: @project.cancelled_at,
      created_at: @project.created_at,
      updated_at: @project.updated_at
    }
  end
end
