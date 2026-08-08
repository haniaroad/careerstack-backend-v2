# frozen_string_literal: true

module Tasks
  class Unassign
    def self.call(task:, actor:)
      new(task: task, actor: actor).call
    end

    def initialize(task:, actor:)
      @task = task
      @actor = actor
    end

    def call
      project = @task.project
      raise DomainError.new("Only the creator can unassign tasks", code: "forbidden", status: :forbidden) unless project.creator_id == @actor.id
      raise DomainError.new("Only pending tasks can be unassigned", code: "validation_error") unless @task.pending?

      @task.update!(assignee: nil)
      @task
    end
  end
end
