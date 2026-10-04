# frozen_string_literal: true

module Api
  module V1
    class TaskAssignmentsController < BaseController
      def update
        task = find_task!
        if params[:assignee_id].present?
          assignee = User.find(params[:assignee_id])
          updated = Tasks::Assign.call(task: task, actor: current_user, assignee: assignee)
        else
          updated = Tasks::Unassign.call(task: task, actor: current_user)
        end
        render json: { task: TaskSerializer.call(updated) }
      end

      private

      def find_task!
        task = Task.includes(:project).find_by(id: params[:task_id])
        raise ActiveRecord::RecordNotFound if task.nil?
        raise ActiveRecord::RecordNotFound unless current_user.member_of_workspace?(task.project.workspace)

        task
      end
    end
  end
end
