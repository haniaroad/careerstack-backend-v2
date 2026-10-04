# frozen_string_literal: true

module Tasks
  class Destroy
    def self.call(task:, actor:)
      new(task: task, actor: actor).call
    end

    def initialize(task:, actor:)
      @task = task
      @actor = actor
    end

    def call
      unless @task.project.creator_id == @actor.id
        raise DomainError.new("Only the project creator can delete this task", code: "forbidden", status: :forbidden)
      end
      raise DomainError.new("Approved tasks cannot be deleted", code: "validation_error") if @task.approved?

      Projects::Lifecycle::ActionGate.assert!(project: @task.project, action: :delete_task)
      @task.destroy!
      true
    end
  end
end
