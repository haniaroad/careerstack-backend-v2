# frozen_string_literal: true

module Api
  module V1
    class PeerReviewsController < BaseController
      def index
        workspace = current_user.resolved_active_workspace
        reviews = if workspace.nil?
          PeerReview.none
        else
          scope = PeerReview.authored_by(current_user).in_workspace(workspace).includes(:project, reviewer: :profile, reviewee: :profile)
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope.order(created_at: :desc)
        end

        render json: { peer_reviews: reviews.map { |review| PeerReviewSerializer.slot(review, viewer: current_user) } }
      end

      def submit
        review = PeerReview.find(params[:id])
        submitted = PeerReviews::Submit.call(
          review: review,
          actor: current_user,
          rating: params.require(:rating),
          comment: params.require(:comment)
        )
        render json: { peer_review: PeerReviewSerializer.slot(submitted, viewer: current_user) }
      end
    end
  end
end
