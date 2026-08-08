# frozen_string_literal: true

module Tasks
  class UnassignMember
    def self.call(project:, user:)
      new(project: project, user: user).call
    end

    def initialize(project:, user:)
      @project = project
      @user = user
    end

    def call
      @project.tasks.where(assignee_id: @user.id, status: Task::STATUS_PENDING).find_each do |task|
        task.update!(assignee: nil)
      end
    end
  end
end
