# frozen_string_literal: true

require "csv"

module OrganizationReports
  class RenderCsv
    def self.call(report:, metrics:)
      new(report: report, metrics: metrics).call
    end

    def initialize(report:, metrics:)
      @report = report
      @metrics = metrics
    end

    def call
      CSV.generate do |csv|
        csv << [ "section", "field", "value", "extra" ]
        csv << [ "meta", "organization_name", @metrics["organization_name"], nil ]
        csv << [ "meta", "program_name", @metrics["program_name"].presence || "All programs", nil ]
        csv << [ "meta", "period_starts_on", @metrics["period_starts_on"], nil ]
        csv << [ "meta", "period_ends_on", @metrics["period_ends_on"], nil ]
        csv << [ "meta", "generated_at", @metrics["generated_at"], nil ]
        csv << [ "meta", "aggregate_only", @report.aggregate_only?.to_s, nil ]
        csv << [ "meta", "methodology_note", @metrics["methodology_note"], nil ]

        aggregates.each do |key, value|
          next if key == "outcomes" || key == "skills_practiced"
          csv << [ "metric", key, format_value(value), nil ]
        end
        csv << [ "metric", "skills_practiced", Array(aggregates["skills_practiced"]).join("|"), nil ]

        Array(aggregates["outcomes"]).each do |type, count|
          csv << [ "outcome_aggregate", type, count.to_s, "self_reported" ]
        end

        next if @report.aggregate_only?

        Array(@metrics["members"]).each do |member|
          csv << [
            "member",
            member["display_name"],
            member["email"],
            [ member["role"], member["age_status"], Array(member["program_names"]).join("|") ].join(";")
          ]
        end

        Array(@metrics["outcomes"]).each do |outcome|
          csv << [
            "outcome",
            outcome["display_name"],
            outcome["email"],
            [
              outcome["outcome_type"],
              outcome["occurred_on"],
              outcome["careerstack_contribution"],
              outcome["institution"],
              outcome["title"],
              outcome["note"],
              "self_reported"
            ].join(";")
          ]
        end
      end
    end

    private

    def aggregates
      @metrics.fetch("aggregates")
    end

    def format_value(value)
      value.nil? ? "" : value.to_s
    end
  end
end
