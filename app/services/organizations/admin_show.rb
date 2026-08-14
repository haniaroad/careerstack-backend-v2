# frozen_string_literal: true

module Organizations
  class AdminShow
    def self.call(organization:, membership:)
      new(organization: organization, membership: membership).call
    end

    def initialize(organization:, membership:)
      @organization = organization
      @membership = membership
    end

    def call
      credits = Credits::Balance.summary(owner: @organization)
      pending_invitations = @organization.invitations.pending.count
      overdue_applications = overdue_application_count
      request = @organization.open_upgrade_request

      {
        organization: OrganizationSerializer.call(@organization),
        capabilities: {
          can_archive_programs: @membership.can_archive_programs?,
          can_delete_empty_drafts: @membership.can_delete_empty_drafts?,
          can_remove_members: @membership.can_remove_members?,
          can_view_credit_history: @membership.can_view_credit_history?,
          can_submit_upgrade_request: @membership.administrator?,
          can_export_reports: @membership.can_export_reports?
        },
        operational_pulse: {
          active_programs: @organization.programs.active.count,
          active_projects: org_projects.where(status: Project::STATUS_ACTIVE).count,
          attention_count: pending_invitations + overdue_applications,
          pending_invitations: pending_invitations,
          overdue_applications: overdue_applications,
          credit_remaining: credits[:remaining],
          credit_label: credit_label(credits)
        },
        credits: credits,
        upgrade_request: request && UpgradeRequestSerializer.call(request)
      }
    end

    private

    def org_projects
      workspace = @organization.workspace
      return Project.none if workspace.nil?

      Project.where(workspace_id: workspace.id)
    end

    def overdue_application_count
      workspace = @organization.workspace
      return 0 if workspace.nil?

      ProjectApplication.pending
        .joins(:project)
        .where(projects: { workspace_id: workspace.id })
        .where.not(overdue_at: nil)
        .count
    end

    def credit_label(credits)
      if credits[:remaining].to_i <= 0
        "Zero credits — new projects and project memberships are blocked"
      elsif credits[:trial_remaining].to_i.positive? && credits[:purchased_remaining].to_i.zero?
        "Trial credits — one creates a project, one adds a project participant; inviting members is free"
      else
        "Pooled organization credits"
      end
    end
  end
end
