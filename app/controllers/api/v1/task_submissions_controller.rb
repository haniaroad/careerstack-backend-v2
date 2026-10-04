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
        task = Task.includes(:project).find_by(id: params[:task_id], assignee_id: current_user.id)
        raise ActiveRecord::RecordNotFound if task.nil?

        project = task.project
        if project.workspace.organization?
          raise ActiveRecord::RecordNotFound unless current_user.member_of_workspace?(project.workspace)
        elsif !project.memberships.active.exists?(user_id: current_user.id)
          raise ActiveRecord::RecordNotFound
        end

        task
      end
    end
  end
end
