# frozen_string_literal: true

require "json"
require "date"

module Ai
  # LLMs frequently emit "today" or past dates even when asked for future ones.
  # Clamp end/due dates into a valid window derived from time_available before schema validation.
  class NormalizeProjectDraftDates
    def self.call(payload, time_available: "2 weeks")
      new(payload, time_available: time_available).call
    end

    def initialize(payload, time_available:)
      @payload = payload.is_a?(String) ? JSON.parse(payload) : payload.deep_dup
      @time_available = time_available.to_s
      @today = Date.current
    rescue JSON::ParserError
      @payload = nil
    end

    def call
      return @payload if @payload.nil? || !@payload.is_a?(Hash)

      end_date = parse_date(@payload["project_end_date"])
      duration = duration_days
      if end_date.nil? || end_date <= @today
        end_date = @today + duration
        @payload["project_end_date"] = end_date.iso8601
      end

      tasks = Array(@payload["proposed_tasks"])
      tasks.each_with_index do |task, index|
        next unless task.is_a?(Hash)

        due = parse_date(task["recommended_due_date"])
        next if due && due > @today && due <= end_date

        task["recommended_due_date"] = spaced_due_date(index: index, total: tasks.size, end_date: end_date).iso8601
      end
      @payload["proposed_tasks"] = tasks
      @payload
    end

    private

    def duration_days
      case @time_available.downcase
      when /1\s*week/ then 7
      when /2\s*weeks/ then 14
      when /1\s*month/ then 30
      when /6\s*weeks/ then 42
      else
        14
      end
    end

    def spaced_due_date(index:, total:, end_date:)
      span = [ (end_date - @today).to_i, 1 ].max
      count = [ total, 1 ].max
      offset = [ ((index + 1).to_f / (count + 1) * span).ceil, 1 ].max
      due = @today + offset
      due = end_date if due > end_date
      due = @today + 1 if due <= @today
      due = end_date if due > end_date
      due
    end

    def parse_date(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
