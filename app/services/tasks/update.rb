# frozen_string_literal: true

module Tasks
  class Update
    def self.call(task:, actor:, attrs:)
      new(task: task, actor: actor, attrs: attrs).call
    end

    def initialize(task:, actor:, attrs:)
      @task = task
      @actor = actor
      @attrs = attrs.to_h.symbolize_keys
    end

    def call
      authorize!
      Projects::Lifecycle::ActionGate.assert!(project: @task.project, action: :update_task)
      @task.update!(changes)
      @task
    end

    private

    def authorize!
      unless @task.project.creator_id == @actor.id
        raise DomainError.new("Only the project creator can edit this task", code: "forbidden", status: :forbidden)
      end
      raise DomainError.new("Approved tasks cannot be edited", code: "validation_error") if @task.approved?
    end

    def changes
      updates = {}
      updates[:title] = title if @attrs.key?(:title)
      updates[:acceptance_criteria] = blank_to_nil(@attrs[:acceptance_criteria]) if @attrs.key?(:acceptance_criteria)
      updates[:submission_expectations] = blank_to_nil(@attrs[:submission_expectations]) if @attrs.key?(:submission_expectations)
      updates[:due_on] = due_on if @attrs.key?(:due_on)
      updates[:reference_video_url] = Tasks::ReferenceVideo.normalize!(@attrs[:reference_video_url]) if @attrs.key?(:reference_video_url)
      raise DomainError.new("No task fields to update", code: "validation_error") if updates.empty?

      updates
    end

    def title
      value = @attrs[:title].to_s.strip
      raise DomainError.new("Title is required", code: "validation_error") if value.blank?
      raise DomainError.new("Title is too long", code: "validation_error") if value.length > 200

      value
    end

    def due_on
      raw = @attrs[:due_on]
      return nil if raw.blank?

      date = Date.iso8601(raw.to_s)
      ends_on = @task.project.ends_on
      if ends_on.present? && date > ends_on
        raise DomainError.new("Due date cannot be after the project end date", code: "validation_error")
      end

      date
    rescue Date::Error
      raise DomainError.new("Due date is invalid", code: "validation_error")
    end

    def blank_to_nil(value)
      text = value.to_s
      text.strip.empty? ? nil : text
    end
  end
end
