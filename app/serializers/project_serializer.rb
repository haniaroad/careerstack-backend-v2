# frozen_string_literal: true

class ProjectSerializer
  def self.call(project, include_tasks: true)
    new(project, include_tasks: include_tasks).as_json
  end

  def initialize(project, include_tasks: true)
    @project = project
    @include_tasks = include_tasks
  end

  def as_json
    payload = {
      id: @project.id,
      title: @project.title,
      summary: @project.summary,
      skills: @project.skills,
      mode: @project.mode,
      status: @project.status,
      source: @project.source,
      objective: @project.objective,
      project_type: @project.project_type,
      expected_duration: @project.expected_duration,
      ends_on: @project.ends_on,
      definition_of_done: @project.definition_of_done,
      roles_needed: @project.roles_needed,
      proposed_tasks: @project.proposed_tasks,
      submission_expectations: @project.submission_expectations,
      ai_generation_succeeded_at: @project.ai_generation_succeeded_at,
      workspace_id: @project.workspace_id,
      creator_id: @project.creator_id,
      confirmed_at: @project.confirmed_at,
      cancelled_at: @project.cancelled_at,
      created_at: @project.created_at,
      updated_at: @project.updated_at
    }
    payload[:tasks] = @project.tasks.order(:position).map { |t| TaskSerializer.call(t) } if @include_tasks
    payload
  end
end
