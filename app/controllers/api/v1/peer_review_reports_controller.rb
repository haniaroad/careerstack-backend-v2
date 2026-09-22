# frozen_string_literal: true

module Api
  module V1
    class PeerReviewReportsController < BaseController
      def create
        review = PeerReview.find(params[:peer_review_id] || params[:id])
        report = PeerReviews::CreateReport.call(
          review: review,
          actor: current_user,
          report_type: params.require(:report_type),
          reason_category: params.require(:reason_category),
          details: params[:details]
        )
        render json: { report: PeerReviewReportSerializer.call(report) }, status: :created
      end
    end
  end
end
