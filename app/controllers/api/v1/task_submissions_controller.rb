# frozen_string_literal: true

module Api
  module V1
    class TaskSubmissionsController < BaseController
      def create
        task = find_assignee_task!
        result = Tasks::Submit.call(
          task: task,
          user: current_user,
          body: params[:body],
          links: params[:links],
          signed_blob_ids: params[:signed_blob_ids]
        )

        render json: {
          task: TaskSerializer.call(result[:task], include_detail: true),
          submission: TaskSubmissionSerializer.call(result[:submission]),
          review: result[:review] ? AiReviewSerializer.call(result[:review]) : nil
        }, status: :created
      end

      private

      def find_assignee_task!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?

        task = Task.in_workspace(workspace).find_by(id: params[:task_id], assignee_id: current_user.id)
        raise ActiveRecord::RecordNotFound if task.nil?

        task
      end
    end
  end
end
