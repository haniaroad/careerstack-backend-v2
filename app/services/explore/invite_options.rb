# frozen_string_literal: true

module Explore
  class InviteOptions
    def self.call(viewer:, target:)
      new(viewer: viewer, target: target).call
    end

    def initialize(viewer:, target:)
      @viewer = viewer
      @target = target
    end

    def call
      if @target.nil? || @target.id == @viewer.id
        return { eligible_projects: [], unavailable: false }
      end

      {
        eligible_projects: eligible_projects.map { |project| card(project) },
        unavailable: ProjectMembership.active_participation?(@target)
      }
    end

    private

    def eligible_projects
      Project.where(creator_id: @viewer.id, mode: Project::MODE_TEAM, status: Project::STATUS_ACTIVE)
        .order(:title)
        .select { |project| project.joinable? && target_may_join?(project) }
    end

    def target_may_join?(project)
      Projects::JoinEligibility.assert_can_join!(project: project, user: @target)
      true
    rescue DomainError
      false
    end

    def card(project)
      {
        id: project.id,
        title: project.title,
        roles_needed: project.roles_needed
      }
    end
  end
end
