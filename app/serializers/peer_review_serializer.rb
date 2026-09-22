# frozen_string_literal: true

class PeerReviewSerializer
  def self.slot(review, viewer:)
    new(review: review, viewer: viewer, public_view: false).slot_json
  end

  def self.public_card(review, viewer: nil, public_view: true)
    new(review: review, viewer: viewer, public_view: public_view).public_json
  end

  def initialize(review:, viewer:, public_view:)
    @review = review
    @viewer = viewer
    @public_view = public_view
  end

  def slot_json
    anonymized = @review.anonymized?
    {
      id: @review.id,
      project_id: @review.project_id,
      project_title: @review.project.title,
      from_user_id: @review.reviewer_id,
      from_user_name: anonymized ? PeerReview::ANONYMIZED_LABEL : @review.reviewer.profile&.display_name,
      to_user_id: @review.reviewee_id,
      to_user_name: anonymized && @review.reviewee_minor? ? PeerReview::ANONYMIZED_LABEL : @review.reviewee.profile&.display_name,
      status: @review.status,
      is_anonymized: anonymized,
      summary: @review.comment.to_s,
      rating: @review.completed? ? @review.rating : nil,
      completed_at: @review.submitted_at
    }
  end

  def public_json
    payload = {
      id: @review.id,
      reviewer_display_name: @review.reviewer_display_name,
      reviewer_is_anonymized: @review.anonymized?,
      project_title: @review.project.title,
      body: @review.comment.to_s,
      created_at: @review.submitted_at
    }
    return payload if @public_view || @viewer.nil? || @viewer.id != @review.reviewee_id

    payload.merge(rating: @review.rating)
  end
end
