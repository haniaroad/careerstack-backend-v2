# frozen_string_literal: true

module PublicProjects
  # Server-side eligibility for unauthenticated public project link access.
  class Resolve
    INELIGIBLE_STATUSES = [
      Project::STATUS_DRAFT,
      Project::STATUS_CANCELLED,
      Project::STATUS_ARCHIVED
    ].freeze

    def self.eligible?(project)
      new(project).eligible?
    end

    def self.find_public!(slug)
      project = Project.includes(:workspace, :creator, :tasks, creator: :profile)
                       .find_by(slug: slug.to_s.downcase)
      raise DomainError.new("Project not found", code: "not_found", status: :not_found) if project.nil?
      raise DomainError.new("Project not found", code: "not_found", status: :not_found) unless eligible?(project)

      project
    end

    def initialize(project)
      @project = project
    end

    def eligible?
      return false if @project.nil?
      return false unless @project.visibility == Project::VISIBILITY_PUBLIC
      return false if INELIGIBLE_STATUSES.include?(@project.status)
      return false unless workspace_allows_public?

      true
    end

    private

    def workspace_allows_public?
      workspace = @project.workspace
      return false if workspace.nil?
      # Personal workspaces may publish public projects. Organization projects
      # are public only when the creator explicitly set visibility=public.
      true
    end
  end
end
