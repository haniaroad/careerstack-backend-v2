# frozen_string_literal: true

module Api
  module V1
    class TaskAssignmentsController < BaseController
      def update
        task = find_creator_task!
        if params[:assignee_id].present?
          assignee = User.find(params[:assignee_id])
          updated = Tasks::Assign.call(task: task, actor: current_user, assignee: assignee)
        else
          updated = Tasks::Unassign.call(task: task, actor: current_user)
        end
        render json: { task: TaskSerializer.call(updated) }
      end

      private

      def require_workspace!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?

        workspace
      end

      def find_creator_task!
        workspace = require_workspace!
        task = Task.in_workspace(workspace).find_by(id: params[:task_id])
        raise ActiveRecord::RecordNotFound if task.nil?
        raise DomainError.new("Only the creator can manage assignments", code: "forbidden", status: :forbidden) unless task.project.creator_id == current_user.id

        task
      end
    end
  end
end
