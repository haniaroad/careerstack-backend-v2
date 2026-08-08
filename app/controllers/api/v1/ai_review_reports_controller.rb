# frozen_string_literal: true

module Api
  module V1
    class AiReviewReportsController < BaseController
      def create
        review = AiReview.find_by(id: params[:ai_review_id] || params[:review_id] || params[:id])
        raise ActiveRecord::RecordNotFound if review.nil?

        report = Ai::CreateReviewReport.call(
          review: review,
          user: current_user,
          report_type: params.require(:report_type),
          reason_category: params.require(:reason_category),
          details: params[:details]
        )
        render json: { report: AiReviewReportSerializer.call(report) }, status: :created
      end
    end
  end
end
