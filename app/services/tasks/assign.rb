# frozen_string_literal: true

module Tasks
  class Assign
    def self.call(task:, actor:, assignee:)
      new(task: task, actor: actor, assignee: assignee).call
    end

    def initialize(task:, actor:, assignee:)
      @task = task
      @actor = actor
      @assignee = assignee
    end

    def call
      project = @task.project
      raise DomainError.new("Only the creator can assign tasks", code: "forbidden", status: :forbidden) unless project.creator_id == @actor.id
      raise DomainError.new("Only team projects use participant assignment", code: "validation_error") unless project.team?
      Projects::Lifecycle::ActionGate.assert!(project: project, action: :assign)
      raise DomainError.new("Only pending tasks can be assigned", code: "validation_error") unless @task.pending?
      raise DomainError.new("Creator cannot be assigned project tasks", code: "validation_error") if @assignee.id == project.creator_id

      membership = project.memberships.active.participants.find_by(user_id: @assignee.id)
      raise DomainError.new("Assignee must be an active participant", code: "validation_error") if membership.nil?

      @task.update!(assignee: @assignee)
      Notifications::Hook.emit(
        event_key: "task_assigned",
        actor: @actor,
        recipients: [ @assignee ],
        source: @task,
        project: project,
        payload: Notifications::Hook.task_payload(@task)
      )
      @task
    end
  end
end
