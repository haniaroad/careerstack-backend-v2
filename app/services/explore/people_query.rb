# frozen_string_literal: true

module Explore
  class PeopleQuery
    def self.call(viewer:, filters: {}, page: 1, per_page: Page::MAX_PER_PAGE)
      new(viewer: viewer, filters: filters, page: page, per_page: per_page).call
    end

    def initialize(viewer:, filters:, page:, per_page:)
      @viewer = viewer
      @filters = filters
      @page, @per_page = Page.parse(page: page, per_page: per_page)
    end

    def call
      scope = searchable.order("profiles.display_name ASC")
      total = scope.count
      users = scope.offset((@page - 1) * @per_page).limit(@per_page).to_a
      labels = public_labels_for(users.map(&:id))
      {
        people: users.map { |user| card(user, labels[user.id]) },
        page: @page,
        per_page: @per_page,
        total_count: total
      }
    end

    private

    def searchable
      scope = User.joins(:profile).includes(profile: :current_role_term)
        .where(status: User::ACTIVE, age_status: AgeStatusCalculator::ADULT)
        .where.not(id: @viewer.id)
        .where(<<~SQL.squish)
          users.onboarding_path = 'independent'
          OR EXISTS (
            SELECT 1 FROM age_visibility_preferences avp
            WHERE avp.user_id = users.id
              AND avp.public_identity_confirmed = TRUE
          )
        SQL
      apply_filters(scope)
    end

    def apply_filters(scope)
      name = @filters[:name].to_s.strip
      scope = scope.where("profiles.display_name ILIKE ?", like(name)) if name.present?

      experience = @filters[:experience].to_s.strip
      if experience.present?
        scope = scope.where(profiles: { experience_level: experience })
      end

      location = @filters[:location].to_s.strip
      if location.present?
        pattern = like(location)
        scope = scope.where(
          "profiles.state_region ILIKE :q OR profiles.country ILIKE :q",
          q: pattern
        )
      end

      role = @filters[:role].to_s.strip
      if role.present?
        pattern = like(role)
        scope = scope.where(<<~SQL.squish, q: pattern)
          profiles.current_role_other ILIKE :q
          OR EXISTS (
            SELECT 1 FROM taxonomy_terms tt
            WHERE tt.id = profiles.current_role_term_id
              AND (tt.label ILIKE :q OR tt.key ILIKE :q)
          )
        SQL
      end

      skill = @filters[:skill].to_s.strip
      scope = scope.where(skill_exists_sql, [ skill ].to_json) if skill.present?

      organization = @filters[:organization].to_s.strip
      if organization.present?
        scope = scope.where(organization_exists_sql, org: like(organization))
      end

      scope
    end

    def skill_exists_sql
      <<~SQL.squish
        EXISTS (
          SELECT 1 FROM project_memberships pm
          INNER JOIN projects p ON p.id = pm.project_id
          WHERE pm.user_id = users.id
            AND p.visibility = 'public'
            AND p.status NOT IN ('draft', 'cancelled', 'archived')
            AND p.skills @> ?::jsonb
        )
      SQL
    end

    def organization_exists_sql
      <<~SQL.squish
        EXISTS (
          SELECT 1 FROM project_memberships pm
          INNER JOIN projects p ON p.id = pm.project_id
          INNER JOIN workspaces w ON w.id = p.workspace_id
          INNER JOIN organizations o ON o.id = w.organization_id
          WHERE pm.user_id = users.id
            AND p.visibility = 'public'
            AND p.status NOT IN ('draft', 'cancelled', 'archived')
            AND o.name ILIKE :org
        )
      SQL
    end

    def public_labels_for(user_ids)
      return {} if user_ids.empty?

      labels = Hash.new { |hash, key| hash[key] = { organizations: [], skills: [] } }
      skill_rows = ProjectMembership.joins(:project)
        .where(user_id: user_ids)
        .where(projects: { visibility: Project::VISIBILITY_PUBLIC })
        .where.not(projects: { status: [ Project::STATUS_DRAFT, Project::STATUS_CANCELLED, Project::STATUS_ARCHIVED ] })
        .pluck("project_memberships.user_id", "projects.skills")
      skill_rows.each do |user_id, skills|
        labels[user_id][:skills].concat(Array(skills))
      end

      org_rows = ProjectMembership.joins(project: { workspace: :organization })
        .where(user_id: user_ids)
        .where(projects: { visibility: Project::VISIBILITY_PUBLIC })
        .where.not(projects: { status: [ Project::STATUS_DRAFT, Project::STATUS_CANCELLED, Project::STATUS_ARCHIVED ] })
        .pluck("project_memberships.user_id", "organizations.name")
      org_rows.each do |user_id, org_name|
        labels[user_id][:organizations] << org_name if org_name.present?
      end
      labels
    end

    def card(user, label)
      profile = user.profile
      organizations = Array(label && label[:organizations]).uniq.sort
      skills = Array(label && label[:skills]).map(&:to_s).uniq.sort
      role = profile.current_role_other.presence || profile.current_role_term&.label
      {
        user_id: user.id,
        slug: profile.slug,
        display_name: profile.display_name,
        image_url: profile.image_url,
        location: [ profile.state_region, profile.country ].compact_blank.join(", "),
        timezone: user.timezone,
        role: role,
        experience_level: profile.experience_level,
        skills: skills,
        organizations: organizations
      }
    end

    def like(value)
      "%#{ActiveRecord::Base.sanitize_sql_like(value)}%"
    end
  end
end
