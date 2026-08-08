# frozen_string_literal: true

module Ai
  class TaskReviewJob < ApplicationJob
    queue_as :default

    def perform(review_id)
      review = AiReview.find_by(id: review_id)
      return if review.nil?

      Ai::RunTaskReview.call(review: review)
    end
  end
end
