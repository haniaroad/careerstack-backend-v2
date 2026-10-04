# frozen_string_literal: true

module Api
  module V1
    class TasksController < BaseController
      def index
        workspace = require_workspace!
        tasks = visible_tasks(workspace).includes(:project).order(updated_at: :desc)
        render json: { tasks: tasks.map { |t| TaskSerializer.call(t) } }
      end

      def show
        task = find_accessible_task!
        render json: { task: TaskSerializer.call(task, include_detail: true) }
      end

      private

      def require_workspace!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?

        workspace
      end

      def find_accessible_task!
        task = Task.includes(:project).find_by(id: params[:id])
        raise ActiveRecord::RecordNotFound if task.nil?
        raise ActiveRecord::RecordNotFound unless accessible_task?(task)

        task
      end

      def visible_tasks(workspace)
        assigned = Task.for_assignee(current_user)
        in_workspace_ids = assigned.joins(:project).where(projects: { workspace_id: workspace.id }).select("tasks.id")
        return Task.where(id: in_workspace_ids) unless workspace.personal?

        joined_personal_ids = assigned
          .joins(project: [ :workspace, :memberships ])
          .where(workspaces: { kind: "personal" })
          .where(project_memberships: { user_id: current_user.id, status: ProjectMembership::STATUS_ACTIVE })
          .select("tasks.id")

        Task.where(id: in_workspace_ids).or(Task.where(id: joined_personal_ids))
      end

      def accessible_task?(task)
        project = task.project
        if project.workspace.organization?
          return false unless current_user.member_of_workspace?(project.workspace)
        end

        task.assignee_id == current_user.id ||
          project.creator_id == current_user.id ||
          project.memberships.active.exists?(user_id: current_user.id)
      end
    end
  end
end
