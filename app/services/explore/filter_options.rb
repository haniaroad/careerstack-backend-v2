# frozen_string_literal: true

module Explore
  # System lists for Explore dropdowns. Values match the filters the directory applies.
  class FilterOptions
    EXPERIENCE_LEVELS = %w[beginner intermediate advanced].freeze

    def self.call
      {
        skills: skills,
        roles: roles,
        experience_levels: EXPERIENCE_LEVELS,
        locations: locations,
        organizations: organizations
      }
    end

    def self.skills
      taxonomy_labels("skills")
    end

    def self.roles
      taxonomy_labels("roles")
    end

    def self.taxonomy_labels(key)
      Taxonomy.find_by(key: key)&.taxonomy_terms&.order(:position)&.pluck(:label) || []
    end

    def self.locations
      regions = Profile.where.not(state_region: [ nil, "" ]).distinct.pluck(:state_region)
      countries = Profile.where.not(country: [ nil, "" ]).distinct.pluck(:country)
      (regions + countries).map { |value| value.to_s.strip }.reject(&:blank?).uniq.sort
    end

    def self.organizations
      ids = Project.joins(:workspace)
        .where(visibility: Project::VISIBILITY_PUBLIC)
        .where.not(status: [ Project::STATUS_DRAFT, Project::STATUS_CANCELLED, Project::STATUS_ARCHIVED ])
        .where.not(workspaces: { organization_id: nil })
        .distinct
        .pluck("workspaces.organization_id")
      Organization.where(id: ids).order(:name).pluck(:name)
    end

    def self.listed(rows)
      rows.flatten.compact.map { |value| value.to_s.strip }.reject(&:blank?).uniq.sort
    end
    private_class_method :listed
  end
end
