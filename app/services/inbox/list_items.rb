# frozen_string_literal: true

module Inbox
  class ListItems
    CATEGORIES = %w[task_review application invitation alert].freeze
    URGENCY_RANK = { "critical" => 0, "high" => 1, "medium" => 2, "low" => 3 }.freeze
    APPLICATION_TARGET = 72.hours
    REVIEW_TARGET = 72.hours

    Item = Struct.new(
      :id,
      :category,
      :related_id,
      :project_id,
      :project_title,
      :title,
      :description,
      :status_label,
      :urgency,
      :is_overdue,
      :cta_label,
      :created_at,
      :payload,
      keyword_init: true
    )

    def self.call(workspace:, user:, category: nil, limit: 50)
      new(workspace: workspace, user: user, category: category, limit: limit).call
    end

    def initialize(workspace:, user:, category:, limit:)
      @workspace = workspace
      @user = user
      @category = category.presence
      @limit = limit.clamp(1, 100)
    end

    def call
      if @category.present? && CATEGORIES.exclude?(@category)
        raise DomainError.new("Invalid inbox category", code: "validation_error")
      end

      items = []
      items.concat(task_review_items) if include?("task_review")
      items.concat(application_items) if include?("application")
      items.concat(invitation_items) if include?("invitation")
      items.concat(alert_items) if include?("alert")

      sorted = items.sort_by { |item| [ item.is_overdue ? 0 : 1, URGENCY_RANK.fetch(item.urgency, 9), -item.created_at.to_i ] }
      sorted.first(@limit)
    end

    private

    def include?(category)
      @category.nil? || @category == category
    end

    def task_review_items
      Task.joins(:project)
          .where(projects: { workspace_id: @workspace.id, creator_id: @user.id, mode: Project::MODE_TEAM, status: Project::STATUS_ACTIVE })
          .where(status: Task::STATUS_SUBMITTED)
          .includes(:project, :assignee)
          .map { |task| serialize_task_review(task) }
    end

    def application_items
      ProjectApplication.joins(:project)
                        .pending
                        .where(projects: { workspace_id: @workspace.id, creator_id: @user.id })
                        .includes(:project, :applicant)
                        .map { |application| serialize_application(application) }
    end

    def invitation_items
      ProjectInvitation.joins(:project)
                       .where(status: ProjectInvitation::STATUS_PENDING, invitee_id: @user.id)
                       .where(projects: { workspace_id: @workspace.id })
                       .includes(:project)
                       .map { |invitation| serialize_invitation(invitation) }
    end

    def alert_items
      scope = InboxAlert.where(workspace_id: @workspace.id)
      user_alerts = scope.where(audience: InboxAlert::AUDIENCE_USER, recipient_user_id: @user.id)
      org_alerts = if @workspace.organization? && @user.can_access_org_admin_for?(@workspace)
        scope.where(audience: InboxAlert::AUDIENCE_ORG_STAFF, organization_id: @workspace.organization_id)
      else
        InboxAlert.none
      end

      user_alerts.or(org_alerts).order(created_at: :desc).limit(100).map { |alert| serialize_alert(alert) }
    end

    def serialize_task_review(task)
      overdue = task.review_overdue_at.present? || overdue_by_age?(task.first_submitted_at, REVIEW_TARGET)
      Item.new(
        id: "task_review:#{task.id}",
        category: "task_review",
        related_id: task.id,
        project_id: task.project_id,
        project_title: task.project.title,
        title: task.title,
        description: "Submitted work awaiting creator review",
        status_label: overdue ? "Review overdue" : "Awaiting review",
        urgency: overdue ? "high" : "medium",
        is_overdue: overdue,
        cta_label: "Review submission",
        created_at: task.first_submitted_at || task.updated_at,
        payload: {
          task_id: task.id,
          assignee_id: task.assignee_id,
          first_submitted_at: task.first_submitted_at
        }
      )
    end

    def serialize_application(application)
      overdue = application.overdue_at.present? || overdue_by_age?(application.created_at, APPLICATION_TARGET)
      Item.new(
        id: "application:#{application.id}",
        category: "application",
        related_id: application.id,
        project_id: application.project_id,
        project_title: application.project.title,
        title: "Application for #{application.requested_role}",
        description: "Pending join application",
        status_label: overdue ? "Response overdue" : "Pending decision",
        urgency: overdue ? "high" : "medium",
        is_overdue: overdue,
        cta_label: "Review application",
        created_at: application.created_at,
        payload: {
          application_id: application.id,
          applicant_id: application.applicant_id,
          requested_role: application.requested_role,
          motivation: application.motivation,
          project_id: application.project_id
        }
      )
    end

    def serialize_invitation(invitation)
      Item.new(
        id: "invitation:#{invitation.id}",
        category: "invitation",
        related_id: invitation.id,
        project_id: invitation.project_id,
        project_title: invitation.project.title,
        title: "Invitation to join as #{invitation.requested_role}",
        description: "Pending project invitation",
        status_label: "Invitation pending",
        urgency: "medium",
        is_overdue: false,
        cta_label: "Respond",
        created_at: invitation.created_at,
        payload: {
          invitation_id: invitation.id,
          requested_role: invitation.requested_role,
          project_id: invitation.project_id
        }
      )
    end

    def serialize_alert(alert)
      Item.new(
        id: "alert:#{alert.id}",
        category: "alert",
        related_id: alert.id,
        project_id: alert.project_id,
        project_title: alert.project&.title || "Workspace",
        title: alert.title,
        description: alert.body,
        status_label: alert.kind.humanize,
        urgency: alert.urgency,
        is_overdue: alert.overdue,
        cta_label: "View",
        created_at: alert.created_at,
        payload: {
          alert_id: alert.id,
          kind: alert.kind,
          subject_type: alert.subject_type,
          subject_id: alert.subject_id
        }
      )
    end

    def overdue_by_age?(timestamp, threshold)
      timestamp.present? && timestamp < threshold.ago
    end
  end
end
