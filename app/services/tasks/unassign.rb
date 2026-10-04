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
      creator = project.creator_id == @actor.id
      self_release = @task.assignee_id == @actor.id && @actor.id != project.creator_id
      unless creator || self_release
        raise DomainError.new("Only the creator or the current assignee can release this task", code: "forbidden", status: :forbidden)
      end

      Projects::Lifecycle::ActionGate.assert!(project: project, action: :assign)
      raise DomainError.new("Only pending tasks can be unassigned", code: "validation_error") unless @task.pending?

      @task.update!(assignee: nil)
      @task
    end
  end
end
