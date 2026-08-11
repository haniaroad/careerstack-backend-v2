# frozen_string_literal: true

module Tasks
  class MaterializeFromProposed
    def self.call(project:, assignee:)
      new(project: project, assignee: assignee).call
    end

    def initialize(project:, assignee:)
      @project = project
      @assignee = assignee
    end

    def call
      return @project.tasks.order(:position).to_a if @project.tasks.exists?

      Array(@project.proposed_tasks).each_with_index.map do |raw, index|
        task_hash = raw.is_a?(Hash) ? raw.with_indifferent_access : {}
        title = task_hash[:title].presence || "Task #{index + 1}"
        due_on = parse_date(task_hash[:recommended_due_date])
        if due_on.present? && @project.ends_on.present? && due_on > @project.ends_on
          due_on = @project.ends_on
        end

        Task.create!(
          project: @project,
          assignee: @assignee,
          title: title.to_s.truncate(200),
          acceptance_criteria: task_hash[:summary].presence || task_hash[:acceptance_criteria],
          submission_expectations: task_hash[:submission_expectations].presence || @project.submission_expectations,
          due_on: due_on,
          status: Task::STATUS_PENDING,
          position: index
        )
      end
    end

    private

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
