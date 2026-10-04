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
      creator = project.creator_id == @actor.id
      self_claim = !creator && @assignee.id == @actor.id
      unless creator || self_claim
        raise DomainError.new("Only the creator can assign tasks to someone else", code: "forbidden", status: :forbidden)
      end

      raise DomainError.new("Only team projects use participant assignment", code: "validation_error") unless project.team?
      Projects::Lifecycle::ActionGate.assert!(project: project, action: :assign)
      raise DomainError.new("Only pending tasks can be assigned", code: "validation_error") unless @task.pending?
      raise DomainError.new("Creator cannot be assigned project tasks", code: "validation_error") if @assignee.id == project.creator_id

      membership = project.memberships.active.participants.find_by(user_id: @assignee.id)
      raise DomainError.new("Assignee must be an active participant", code: "validation_error") if membership.nil?

      if self_claim
        claim!
      else
        @task.update!(assignee: @assignee)
      end

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

    private

    def claim!
      Task.transaction do
        locked = Task.lock.find(@task.id)
        unless locked.pending? && locked.assignee_id.nil?
          raise DomainError.new("This task is already assigned", code: "conflict", status: :conflict)
        end

        locked.update!(assignee: @assignee)
        @task = locked
      end
    end
  end
end
