# frozen_string_literal: true

require "json"
require "date"

module Ai
  class ValidateProjectDraft
    REQUIRED_KEYS = %w[
      title
      summary
      learning_objective
      project_type
      expected_duration
      project_end_date
      definition_of_done
      skills_demonstrated
      roles_needed
      proposed_tasks
      submission_expectations
    ].freeze

    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = payload.is_a?(String) ? JSON.parse(payload) : payload
    rescue JSON::ParserError
      @payload = nil
    end

    def call
      raise schema_error("Generation output was not valid JSON") if @payload.nil? || !@payload.is_a?(Hash)

      REQUIRED_KEYS.each do |key|
        raise schema_error("Missing required field: #{key}") unless @payload.key?(key)
      end

      end_date = parse_date!(@payload["project_end_date"], field: "project_end_date")
      raise schema_error("project_end_date must be in the future") unless end_date > Date.current

      tasks = @payload["proposed_tasks"]
      raise schema_error("proposed_tasks must be a non-empty array") unless tasks.is_a?(Array) && tasks.any?

      tasks.each_with_index do |task, index|
        raise schema_error("proposed_tasks[#{index}] must be an object") unless task.is_a?(Hash)
        %w[title summary recommended_due_date submission_expectations].each do |key|
          raise schema_error("proposed_tasks[#{index}].#{key} is required") if task[key].blank?
        end
        due = parse_date!(task["recommended_due_date"], field: "proposed_tasks[#{index}].recommended_due_date")
        raise schema_error("proposed_tasks[#{index}].recommended_due_date must be in the future") unless due > Date.current
        raise schema_error("proposed_tasks[#{index}].recommended_due_date must be on or before project_end_date") if due > end_date
      end

      @payload
    end

    private

    def parse_date!(value, field:)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      raise schema_error("#{field} must be an ISO date (YYYY-MM-DD)")
    end

    def schema_error(message)
      DomainError.new(message, code: "ai_schema_invalid", status: :unprocessable_entity)
    end
  end
end
