# frozen_string_literal: true

# Redacted public project DTO for anonymous visitors (P-05).
class PublicProjectSerializer
  def self.call(project)
    new(project).as_json
  end

  def initialize(project)
    @project = project
  end

  def as_json
    {
      id: @project.id,
      slug: @project.slug,
      title: @project.title,
      summary: @project.summary,
      definition_of_done: @project.definition_of_done,
      skills: @project.skills,
      roles_needed: @project.roles_needed,
      project_type: @project.project_type,
      mode: @project.mode,
      status: @project.status,
      phase: @project.phase,
      joining_mode: @project.joining_mode,
      capacity: @project.capacity,
      seats_remaining: @project.team? ? @project.seats_remaining : nil,
      recruitment_state: @project.recruitment_state,
      ends_on: @project.ends_on,
      tasks: public_tasks,
      creator: creator_json,
      canonical_path: "/projects/#{@project.slug}",
      indexable: true
    }
  end

  private

  def public_tasks
    @project.tasks.order(:position).map do |task|
      {
        title: task.title,
        acceptance_criteria: task.acceptance_criteria
      }
    end
  end

  def creator_json
    creator = @project.creator
    profile = creator&.profile
    display_name = profile&.display_name.presence || "CareerStack member"
    payload = { display_name: display_name, profile_slug: nil }

    if creator && Profiles::Visibility.public_adult?(creator) && profile&.slug.present?
      payload[:profile_slug] = profile.slug
    end

    payload
  end
end
