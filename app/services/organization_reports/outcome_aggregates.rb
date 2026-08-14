# frozen_string_literal: true

module OrganizationReports
  class OutcomeAggregates
    def self.call(organization:, program_id: nil)
      scope = organization.self_reported_outcomes
      scope = scope.where(program_id: program_id) if program_id.present?
      counts = SelfReportedOutcome::TYPES.index_with { 0 }
      scope.group(:outcome_type).count.each { |type, count| counts[type] = count if counts.key?(type) }

      counts.filter_map do |type, count|
        next if count.to_i <= 0

        {
          outcome_type: type,
          label: SelfReportedOutcome::LABELS.fetch(type, type.humanize),
          count: count,
          reporting_label: SelfReportedOutcome::REPORTING_LABEL
        }
      end
    end
  end
end
