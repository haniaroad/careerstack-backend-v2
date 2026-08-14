# frozen_string_literal: true

class SelfReportedOutcomeSerializer
  def self.call(outcome)
    {
      id: outcome.id,
      organization_id: outcome.organization_id,
      program_id: outcome.program_id,
      project_id: outcome.project_id,
      outcome_type: outcome.outcome_type,
      label: outcome.label,
      occurred_on: outcome.occurred_on,
      month: outcome.occurred_on.month,
      year: outcome.occurred_on.year,
      careerstack_contribution: outcome.careerstack_contribution,
      institution: outcome.institution,
      title: outcome.title,
      note: outcome.note,
      reporting_label: outcome.reporting_label
    }
  end
end
