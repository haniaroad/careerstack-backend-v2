# frozen_string_literal: true

module Api
  module V1
    class CreatorReviewsController < BaseController
      def create
        task = find_task!
        updated = Tasks::CreatorReview.call(
          task: task,
          actor: current_user,
          decision: params.require(:decision),
          feedback: params[:feedback]
        )
        render json: { task: TaskSerializer.call(updated, include_detail: true) }
      end

      private

      def require_workspace!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?

        workspace
      end

      def find_task!
        workspace = require_workspace!
        task = Task.in_workspace(workspace).includes(:project).find_by(id: params[:task_id])
        raise ActiveRecord::RecordNotFound if task.nil?

        task
      end
    end
  end
end
