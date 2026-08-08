# frozen_string_literal: true

module Api
  module V1
    class AiReviewsController < BaseController
      def create
        task = find_assignee_task!
        submission = task.submissions.order(:attempt_number).last
        raise DomainError.new("Submit evidence before requesting review", code: "validation_error") if submission.nil?

        review = Ai::CreateTaskReview.call(
          task: task,
          submission: submission,
          user: current_user,
          auto: false
        )
        render json: { review: AiReviewSerializer.call(review) }, status: :accepted
      end

      def show
        review = AiReview.find_by(id: params[:id])
        raise ActiveRecord::RecordNotFound if review.nil?
        raise ActiveRecord::RecordNotFound unless review.owner?(current_user)

        render json: { review: AiReviewSerializer.call(review) }
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
