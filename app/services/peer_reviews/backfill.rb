# frozen_string_literal: true

module PeerReviews
  class Backfill
    def self.call
      Project.where(status: Project::STATUS_COMPLETED, mode: Project::MODE_TEAM).find_each do |project|
        OpenSlots.call(project: project, emit: false)
      end
    end
  end
end
