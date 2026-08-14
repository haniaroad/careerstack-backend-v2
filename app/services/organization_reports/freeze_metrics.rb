# frozen_string_literal: true

module OrganizationReports
  class FreezeMetrics
    def self.call(report:)
      new(report: report).call
    end

    def initialize(report:)
      @report = report
      @organization = report.organization
    end

    def call
      members = named_members
      {
        "organization_name" => @organization.name,
        "program_name" => @report.program&.name,
        "period_starts_on" => @report.period_starts_on.iso8601,
        "period_ends_on" => @report.period_ends_on.iso8601,
        "generated_at" => Time.current.iso8601,
        "methodology_note" => OrganizationReport::METHODOLOGY_NOTE,
        "includes_org_logo" => @organization.logo_url.present?,
        "aggregates" => aggregates,
        "members" => @report.aggregate_only? ? [] : members,
        "outcomes" => @report.aggregate_only? ? [] : named_outcomes
      }
    end

    def includes_minor_names?(metrics)
      return false if @report.aggregate_only?

      Array(metrics["members"]).any? { |row| row["age_status"] == AgeStatusCalculator::MINOR }
    end

    private

    def projects
      @projects ||= begin
        scope = org_projects.where.not(status: Project::STATUS_DRAFT)
        scope = scope.where(program_id: @report.program_id) if @report.program_id.present?
        scope
      end
    end

    def org_projects
      workspace = @organization.workspace
      return Project.none if workspace.nil?

      Project.where(workspace_id: workspace.id)
    end

    def memberships
      scope = @organization.organization_memberships.active.includes(:user, :enrolled_programs)
      if @report.program_id.present?
        scope = scope.joins(:program_enrollments).where(program_enrollments: { program_id: @report.program_id })
      end
      scope
    end

    def enrolled_participants
      memberships.where(role: OrganizationMembership::PARTICIPANT)
    end

    def started_projects
      projects.select { |project| in_period?(project.confirmed_at || project.created_at) }
    end

    def completed_projects
      projects.select { |project| project.completed? && in_period?(project.completed_at) }
    end

    def tasks
      @tasks ||= Task.where(project_id: projects.select(:id))
    end

    def assigned_tasks
      tasks.where.not(assignee_id: nil)
    end

    def aggregates
      enrolled = enrolled_participants.count
      with_completed = participants_with_completed_project
      started = started_projects.size
      completed = completed_projects.size
      assigned = assigned_tasks.count
      approved = assigned_tasks.where(status: Task::STATUS_APPROVED).count
      submitted = assigned_tasks.where.not(first_submitted_at: nil)
      on_time = submitted.where(on_time: true).count
      late = submitted.where(on_time: false).count
      submitted_count = submitted.count

      {
        "enrolled_participants" => enrolled,
        "participants_with_completed_project" => with_completed,
        "participant_completion_rate" => rate(with_completed, enrolled),
        "projects_started" => started,
        "projects_completed" => completed,
        "project_completion_rate" => rate(completed, started),
        "tasks_assigned" => assigned,
        "tasks_approved" => approved,
        "task_approval_rate" => rate(approved, assigned),
        "on_time_submissions" => on_time,
        "late_submissions" => late,
        "on_time_rate" => rate(on_time, submitted_count),
        "artifacts_produced" => artifact_count,
        "skills_practiced" => skills_practiced,
        "outcomes" => outcome_counts
      }
    end

    def participants_with_completed_project
      user_ids = ProjectMembership.where(project_id: completed_projects.map(&:id)).distinct.pluck(:user_id)
      user_ids |= completed_projects.map(&:creator_id)
      enrolled_participants.where(user_id: user_ids).count
    end

    def artifact_count
      task_ids = assigned_tasks.select(:id)
      files = ActiveStorage::Attachment.where(record_type: "TaskSubmission", name: "files")
        .joins("INNER JOIN task_submissions ON task_submissions.id = active_storage_attachments.record_id")
        .where(task_submissions: { task_id: task_ids })
        .count
      links = TaskSubmissionLink.joins(:task_submission).where(task_submissions: { task_id: task_ids }).count
      files + links
    end

    def skills_practiced
      projects.flat_map { |project| Array(project.skills) }.map(&:to_s).map(&:strip).reject(&:blank?).uniq.sort
    end

    def outcome_scope
      scope = @organization.self_reported_outcomes.where(occurred_on: @report.period_starts_on..@report.period_ends_on)
      scope = scope.where(program_id: @report.program_id) if @report.program_id.present?
      scope
    end

    def outcome_counts
      counts = SelfReportedOutcome::TYPES.index_with { 0 }
      outcome_scope.group(:outcome_type).count.each { |type, count| counts[type] = count if counts.key?(type) }
      counts
    end

    def named_members
      memberships.includes(user: :profile).map do |membership|
        {
          "display_name" => membership.user.profile&.display_name,
          "email" => membership.user.email,
          "role" => membership.role,
          "age_status" => membership.user.age_status,
          "program_names" => membership.enrolled_programs.order(:name).map(&:name)
        }
      end
    end

    def named_outcomes
      outcome_scope.includes(:user).map do |outcome|
        {
          "display_name" => outcome.user.profile&.display_name,
          "email" => outcome.user.email,
          "outcome_type" => outcome.outcome_type,
          "label" => outcome.label,
          "occurred_on" => outcome.occurred_on.iso8601,
          "careerstack_contribution" => outcome.careerstack_contribution,
          "institution" => outcome.institution,
          "title" => outcome.title,
          "note" => outcome.note,
          "reporting_label" => SelfReportedOutcome::REPORTING_LABEL
        }
      end
    end

    def in_period?(timestamp)
      return false if timestamp.blank?

      date = timestamp.to_date
      date >= @report.period_starts_on && date <= @report.period_ends_on
    end

    def rate(numerator, denominator)
      return nil if denominator.to_i <= 0

      (numerator.to_f / denominator).round(4)
    end
  end
end
