# frozen_string_literal: true

module PeerReviews
  class Submit
    def self.call(review:, actor:, rating:, comment:)
      new(review: review, actor: actor, rating: rating, comment: comment).call
    end

    def initialize(review:, actor:, rating:, comment:)
      @review = review
      @actor = actor
      @rating = rating
      @comment = comment.to_s.strip
    end

    def call
      raise DomainError.new("Only the reviewer can submit this review", code: "forbidden", status: :forbidden) unless @review.reviewer_id == @actor.id
      raise DomainError.new("Peer reviews are only available after a team project completes", code: "validation_error") unless @review.project.completed? && @review.project.team?
      raise DomainError.new("This review was already submitted", code: "validation_error") if @review.completed?
      raise DomainError.new("Rating must be between 1 and 5", code: "validation_error") unless PeerReview::RATINGS.include?(@rating.to_i)
      raise DomainError.new("Comment is required", code: "validation_error") if @comment.blank?

      @review.update!(
        status: PeerReview::STATUS_COMPLETED,
        rating: @rating.to_i,
        comment: @comment,
        submitted_at: Time.current
      )

      Profiles::RecordContribution.call(
        user: @actor,
        kind: ContributionEvent::KIND_PEER_REVIEW_SUBMITTED,
        subject: @review,
        occurred_at: @review.submitted_at,
        project: @review.project
      )

      Notifications::Hook.emit(
        event_key: "peer_review_received",
        actor: @actor,
        recipients: [ @review.reviewee ],
        source: @review,
        project: @review.project,
        payload: Notifications::Hook.project_payload(
          @review.project,
          "reviewer_label" => @review.reviewer_display_name,
          "slug" => @review.reviewee.profile&.slug.to_s
        )
      )

      @review
    end
  end
end
