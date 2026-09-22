# frozen_string_literal: true

module PeerReviews
  class OpenSlots
    def self.call(project:, emit: true)
      new(project: project, emit: emit).call
    end

    def initialize(project:, emit:)
      @project = project
      @emit = emit
    end

    def call
      return [] unless @project.team? && @project.completed?

      user_ids = @project.memberships.active.pluck(:user_id).uniq
      return [] if user_ids.size < 2

      now = Time.current
      rows = user_ids.product(user_ids).filter_map do |reviewer_id, reviewee_id|
        next if reviewer_id == reviewee_id

        {
          id: SecureRandom.uuid,
          project_id: @project.id,
          reviewer_id: reviewer_id,
          reviewee_id: reviewee_id,
          status: PeerReview::STATUS_AVAILABLE,
          created_at: now,
          updated_at: now
        }
      end

      PeerReview.insert_all(rows, unique_by: [ :project_id, :reviewer_id, :reviewee_id ]) if rows.any?
      notify_request! if @emit
      PeerReview.where(project_id: @project.id, reviewer_id: user_ids)
    end

    private

    def notify_request!
      user_ids = PeerReview.where(project_id: @project.id, status: PeerReview::STATUS_AVAILABLE).distinct.pluck(:reviewer_id)
      return if user_ids.empty?

      Notifications::Hook.emit(
        event_key: "peer_review_request",
        actor: nil,
        recipients: User.where(id: user_ids),
        source: @project,
        project: @project,
        payload: Notifications::Hook.project_payload(@project)
      )
    end
  end
end
