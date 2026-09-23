# frozen_string_literal: true

module Explore
  class ProjectsQuery
    DISCOVERABLE_STATUSES = [
      Project::STATUS_ACTIVE,
      Project::STATUS_COMPLETED,
      Project::STATUS_EXPIRED
    ].freeze

    def self.call(viewer:, workspace:, filters: {}, page: 1, per_page: Page::MAX_PER_PAGE)
      new(viewer: viewer, workspace: workspace, filters: filters, page: page, per_page: per_page).call
    end

    def initialize(viewer:, workspace:, filters:, page:, per_page:)
      @viewer = viewer
      @workspace = workspace
      @filters = filters
      @page, @per_page = Page.parse(page: page, per_page: per_page)
    end

    def call
      scope = discoverable.order(updated_at: :desc)
      total = scope.count
      rows = scope.offset((@page - 1) * @per_page).limit(@per_page)
      {
        projects: rows.map { |project| card(project) },
        page: @page,
        per_page: @per_page,
        total_count: total
      }
    end

    private

    def discoverable
      scope = Project.where(status: DISCOVERABLE_STATUSES)
      scope = apply_workspace(scope)
      scope = apply_filters(scope)
      scope
    end

    def apply_workspace(scope)
      if !@viewer.adult?
        return scope.none if @workspace.personal?

        scope = scope.where(workspace_id: @workspace.id)
      elsif @workspace.personal?
        scope = scope.where(visibility: Project::VISIBILITY_PUBLIC)
      else
        scope = scope.where(workspace_id: @workspace.id)
      end

      return scope unless @workspace.organization?

      program_id = @viewer.membership_for(@workspace.organization)&.program_filter_program_id
      return scope if program_id.blank?

      scope.where(program_id: program_id)
    end

    def apply_filters(scope)
      query = @filters[:q].to_s.strip
      if query.present?
        scope = scope.where("projects.title ILIKE ?", like(query))
      end

      skill = @filters[:skill].to_s.strip
      if skill.present?
        scope = scope.where("projects.skills @> ?", [ skill ].to_json)
      end

      role = @filters[:role].to_s.strip
      if role.present?
        scope = scope.where("projects.roles_needed @> ?", [ role ].to_json)
      end

      scope
    end

    def card(project)
      {
        id: project.id,
        slug: project.slug,
        title: project.title,
        skills: project.skills,
        roles_needed: project.roles_needed,
        joining_mode: project.joining_mode,
        recruitment_state: project.recruitment_state,
        status: project.status,
        phase: project.phase,
        visibility: project.visibility,
        mode: project.mode
      }
    end

    def like(value)
      "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
    end
  end
end
