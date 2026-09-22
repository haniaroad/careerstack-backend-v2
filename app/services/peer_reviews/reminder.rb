# frozen_string_literal: true

module PeerReviews
  class Reminder
    DELAY = 3.days

    def self.call
      new.call
    end

    def call
      pairs = PeerReview.available
                        .where(created_at: ..DELAY.ago)
                        .distinct
                        .pluck(:project_id, :reviewer_id)

      pairs.each do |project_id, reviewer_id|
        next unless PeerReview.available.exists?(project_id: project_id, reviewer_id: reviewer_id)

        project = Project.find_by(id: project_id)
        reviewer = User.find_by(id: reviewer_id)
        next if project.nil? || reviewer.nil? || !project.completed?

        Notifications::Hook.emit(
          event_key: "peer_review_request",
          actor: nil,
          recipients: [ reviewer ],
          source: Notifications::Hook.named_source("peer_review_reminder:#{project_id}"),
          project: project,
          payload: Notifications::Hook.project_payload(project)
        )
      end
    end
  end
end
