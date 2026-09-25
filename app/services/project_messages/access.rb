# frozen_string_literal: true

module ProjectMessages
  class Access
    def self.membership!(project:, user:)
      raise ActiveRecord::RecordNotFound unless project.team?

      membership = project.memberships.active.find_by(user_id: user.id)
      raise ActiveRecord::RecordNotFound if membership.nil?

      membership
    end

    def self.thread_member?(project:, user:)
      return false unless project.team?

      project.memberships.active.exists?(user_id: user.id)
    end
  end
end
