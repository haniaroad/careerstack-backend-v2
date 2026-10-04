# frozen_string_literal: true

module Api
  module V1
    class TasksController < BaseController
      def index
        workspace = require_workspace!
        tasks = Task.in_workspace(workspace).for_assignee(current_user).includes(:project).order(updated_at: :desc)
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

        project = task.project
        raise ActiveRecord::RecordNotFound unless current_user.member_of_workspace?(project.workspace)

        allowed = task.assignee_id == current_user.id ||
          project.creator_id == current_user.id ||
          project.memberships.active.exists?(user_id: current_user.id)
        raise ActiveRecord::RecordNotFound unless allowed

        task
      end
    end
  end
end
