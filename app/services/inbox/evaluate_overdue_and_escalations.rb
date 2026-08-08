# frozen_string_literal: true

module Inbox
  class EvaluateOverdueAndEscalations
    APPLICATION_TARGET = 72.hours
    REVIEW_TARGET = 72.hours
    NO_TASKS_AFTER = 7.days

    def self.call
      new.call
    end

    def call
      mark_application_overdue
      mark_task_review_overdue
      escalate_no_tasks
    end

    private

    def mark_application_overdue
      ProjectApplication.pending
                        .where(overdue_at: nil)
                        .where(created_at: ...APPLICATION_TARGET.ago)
                        .includes(project: :workspace)
                        .find_each do |application|
        project = application.project
        next unless project.active?

        application.update!(overdue_at: Time.current)
        create_creator_reminder!(
          project: project,
          subject: application,
          kind_suffix: "application",
          title: "Application response overdue",
          body: "A join application on #{project.title} has waited more than 72 hours."
        )
        create_escalation!(
          project: project,
          subject: application,
          reason: Escalation::REASON_APPLICATION_OVERDUE
        )
      end
    end

    def mark_task_review_overdue
      Task.where(status: Task::STATUS_SUBMITTED, review_overdue_at: nil)
          .where(first_submitted_at: ...REVIEW_TARGET.ago)
          .includes(project: :workspace)
          .find_each do |task|
        project = task.project
        next unless project.active? && project.team?

        task.update!(review_overdue_at: Time.current)
        create_creator_reminder!(
          project: project,
          subject: task,
          kind_suffix: "task_review",
          title: "Creator review overdue",
          body: "A submission on #{project.title} has waited more than 72 hours for review."
        )
        create_escalation!(
          project: project,
          subject: task,
          reason: Escalation::REASON_TASK_REVIEW_OVERDUE
        )
      end
    end

    def escalate_no_tasks
      Project.active
             .where(mode: Project::MODE_TEAM, confirmed_at: ...NO_TASKS_AFTER.ago)
             .includes(:workspace, :tasks)
             .find_each do |project|
        next if project.tasks.exists?

        create_escalation!(
          project: project,
          subject: project,
          reason: Escalation::REASON_NO_TASKS_CREATED
        )
        create_creator_reminder!(
          project: project,
          subject: project,
          kind_suffix: "no_tasks",
          title: "No tasks created",
          body: "#{project.title} has had no tasks for more than seven days after creation."
        )
      end
    end

    def create_creator_reminder!(project:, subject:, kind_suffix:, title:, body:)
      InboxAlert.find_or_create_by!(idempotency_key: "reminder:#{kind_suffix}:#{subject.class.name}:#{subject.id}") do |alert|
        alert.workspace = project.workspace
        alert.recipient_user_id = project.creator_id
        alert.audience = InboxAlert::AUDIENCE_USER
        alert.kind = InboxAlert::KIND_CREATOR_REMINDER
        alert.subject_type = subject.class.name
        alert.subject_id = subject.id
        alert.project = project
        alert.title = title
        alert.body = body
        alert.urgency = InboxAlert::URGENCY_HIGH
        alert.overdue = true
        alert.organization_id = project.workspace.organization_id
      end
    end

    def create_escalation!(project:, subject:, reason:)
      workspace = project.workspace
      target = workspace.personal? ? Escalation::TARGET_STAFF : Escalation::TARGET_ORGANIZATION
      key = "escalation:#{reason}:#{subject.class.name}:#{subject.id}"

      escalation = Escalation.find_by(idempotency_key: key)
      return escalation if escalation

      escalation = Escalation.create!(
        workspace: workspace,
        project: project,
        target: target,
        organization_id: workspace.organization_id,
        reason: reason,
        subject_type: subject.class.name,
        subject_id: subject.id,
        status: Escalation::STATUS_OPEN,
        idempotency_key: key
      )

      if target == Escalation::TARGET_ORGANIZATION && workspace.organization_id.present?
        InboxAlert.find_or_create_by!(idempotency_key: "alert:#{key}") do |alert|
          alert.workspace = workspace
          alert.organization_id = workspace.organization_id
          alert.audience = InboxAlert::AUDIENCE_ORG_STAFF
          alert.kind = InboxAlert::KIND_ESCALATION
          alert.subject_type = subject.class.name
          alert.subject_id = subject.id
          alert.project = project
          alert.title = "Escalation: #{reason.humanize}"
          alert.body = "#{project.title} needs attention (#{reason.humanize.downcase})."
          alert.urgency = InboxAlert::URGENCY_CRITICAL
          alert.overdue = true
        end
      end

      escalation
    end
  end
end
